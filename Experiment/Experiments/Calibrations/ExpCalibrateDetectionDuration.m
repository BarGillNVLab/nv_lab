classdef ExpCalibrateDetectionDuration < Experiment
    %EXPCALIBRATEDETECTIONDURATION Experiment for calibration of the detection time for measurement 
    
    properties (Constant, Hidden)
        MAX_FREQ = 5e3;   % in MHz (== 5GHz)
        
        MIN_AMPL = -60;   % in dBm
        MAX_AMPL = 3;     % in dBm
        
        MAX_TAU_LENGTH = 1000;
        MIN_TAU = 1e-3;   % in \mus (== 1 ns)
        MAX_TAU = 1e3;    % in \mus (== 1 ms)
    end
    
    properties (Constant)
        NAME = 'Calibration_DetectionDuration';
    end
    
    properties
        % Default values (might change during setup)
        isWithMW = true;    % logical. This Experiment has two modes: one with MW and one without
        
        frequency = 3029;   % in MHz
        amplitude = -10;    % in dBm. Amplitude for the withMW configuration
        
        tau                 % in us
        tauWithMW = 0.010;  % in us (==10 ns)
        tauNoMW = 10e3;     % in us (==10 ms)
        
        laserOnset          % in us. Time for turning on the laser
        
        halfPiTime = 0.025  % in us

        referenceDetectionDuration = 10;	% in us. Detection duration of the reference read
        
        constantTime = false;	% logical
    end
    
    properties (Access = private)
        freqGenName
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    methods
        function obj = ExpCalibrateDetectionDuration(FG)
            obj@Experiment(ExpCalibrateDetectionDuration.NAME);
            
            % First, get a frequency generator
            if nargin == 0; FG = []; end
            obj.freqGenName = obj.getFgName(FG);
            
            % Set properties inherited from Experiment
            obj.repeats = 1000;
            obj.averages = 2000;
            obj.isTracking = true;   % Initialize tracking
            obj.trackThreshhold = 0.7;
            obj.shouldAutosave = true;
            
            obj.detectionDuration = 0.05:0.05:1;      % detection windows, in \mus
            obj.laserInitializationDuration = 20;   % laser initialization in pulsed experiments in us (??)
            obj.getDelays;
            obj.laserOnset = 0.05:0.05:1;
            
            obj.mCurrentXAxisParam = ExpParamDoubleVector('Detection Duration', [], StringHelper.MICROSEC, obj.NAME);
            obj.mCurrentYAxisParam = ExpParamDoubleVector('Laser Onset', [], StringHelper.MICROSEC, obj.NAME);
            obj.signalParam = ExpResultDoubleVector('FL', [], 'normalized', obj.NAME);
            obj.signalParam2 = ExpResultDoubleVector('FL', [], 'normalized', obj.NAME);
        end
    end
    
    %% Setters & Getters
    methods
        function set.frequency(obj, newVal) % newVal is in MHz
            if ~isscalar(newVal)
                obj.sendError('Experiment frequency must be scalar')
            end
            if ~ValidationHelper.isInBorders(newVal, 0, obj.MAX_FREQ)
                errMsg = sprintf(...
                    'Frequency must be between 0 and %d! Frequency reuqested: %d', ...
                    obj.MAX_FREQ, newVal);
                obj.sendError(errMsg);
            end
            % If we got here, then newVal is OK.
            obj.frequency = newVal;
            obj.changeFlag = true;
        end
        
        
        function set.amplitude(obj, newVal) % newVal is in dBm
            if ~isscalar(newVal) || length(newVal) ~= FrequencyGenerator.nAvailable
                obj.sendError('Invalid number of amplitudes for Experiment! Ignoring.')
            end
            if ~ValidationHelper.isInBorders(newVal ,obj.MIN_AMPL, obj.MAX_AMPL)
                errMsg = sprintf(...
                    'Amplitude must be between %d and %d! Amplitude reuqested: %d', ...
                    obj.MIN_AMPL, obj.MAX_AMPL, newVal);
                obj.sendError(errMsg);
            end
            % If we got here, then newVal is OK.
            obj.amplitude = newVal;
            obj.changeFlag = true;
        end
        
        function set.tau(obj ,newVal)	% newVal in microsec
            if ~isscalar(newVal)
                obj.sendError('Tau must be a scalar! Ignoring.')
            end
            if ~ValidationHelper.isInBorders(newVal, obj.MIN_TAU, obj.MAX_TAU)
                errMsg = sprintf(...
                    'All values of Tau must be between %d and %d!', obj.MIN_TAU, obj.MAX_TAU);
                obj.sendError(errMsg);
            end
            % If we got here, then newVal is OK.
            obj.tau = newVal;
            obj.changeFlag = true;
        end
        
        function set.laserOnset(obj, newVal)
            if ~all(newVal>0)
                obj.sendError('Laser onset time must be positive! Ignoring.');
            end
            % If we got here, then newVal is OK.
            obj.laserOnset = newVal;
            obj.changeFlag = true;
        end
        
        function checkDetectionDuration(obj, newVal) %#ok<INUSL>
            % Used in set.detectionDuration. Overriding from superclass
            if ~all(newVal > 0)
                error('DetectionDurations must be strictly positive! Ignoiring.')
            end
        end
        
        
        function tf = isScanLaserOnDelay(obj)
            % If the laserOnset property is scalar, we are not scanning
            % over it, and vice versa.
            tf = ~isscalar(obj.laserOnset);
        end
    end
    
    %% Overridden from Experiment
    methods (Access = protected)
        
        function [signal, sterr] = processData(obj, rawData, duration)
            kc = 1e3;     % kilocounts
            musec = 1e-6;   % microseconds
            
            n = obj.repeats;
            m = length(rawData)/n;  % Number of reads each repeat
            s = (reshape(rawData, m, n))';
            
            signal = mean(s);
            signal = signal./(duration*musec)/kc; %kcounts per second
            
            sterr = ste(s);
            sterr = sterr./(duration*musec)/kc; % convert to kcps
        end
        
        function reset(obj)
            % (Re)initialize signal matrix and inform user we are starting anew
            nMeasPerRepeat1 = length(obj.detectionDuration);
            nMeasPerRepeat2 = length(obj.laserOnset);
            
            obj.signal = zeros(2, nMeasPerRepeat2, nMeasPerRepeat1, obj.averages);
            obj.resetInternal(nMeasPerRepeat1*nMeasPerRepeat2);
        end
        
        function prepare(obj)
            % Initializtions before run
            
            % Sequence
            %%% Useful parameters for what follows
            initDuration = obj.laserInitializationDuration - (min(obj.detectionDuration) + obj.referenceDetectionDuration);
            
            if obj.constantTime
                % The length of the sequence will change when we change
                % the parameter(s). To counter that, we add some
                % delay at the end (mwOffDelay is a property of class
                % Experiment).
                lastDelay = obj.mwOffDelay + max(obj.detectionDuration) + max(obj.laserOnset);
            else
                lastDelay = obj.mwOffDelay;
            end
            
            obj.tau = BooleanHelper.ifTrueElse(obj.isWithMW, obj.tauWithMW, obj.tauNoMW);
            % ^ By saving this as a property, validation for both kinds of
            %   tau is conviently performed with just one setter function
            
            %%% Creating the sequence
            S = Sequence;
            S.addEvent(max(obj.laserOnset), 'greenLaser',                   'onset');     % Calibration of the laser with SPCM (laser on)
            S.addEvent(obj.detectionDuration(end), ...
                                            {'greenLaser', 'detector'},     'detection');   % Detection
            S.addEvent(initDuration,        'greenLaser');                                  % Initialization
            S.addEvent(obj.referenceDetectionDuration, ...
                                            {'greenLaser', 'detector'});                    % Reference detection
            S.addEvent(obj.laserOffDelay);                                                  % Calibration of the laser with SPCM (laser off)
            S.addEvent(obj.halfPiTime,      'MW');                                          % MW before
            S.addEvent(obj.tau,             '');                                            % Delay
            S.addEvent(lastDelay,           '',                             'lastDelay');   % Last delay, making sure the MW is off
            
            %%% Send to PulseGenerator
            pg = getObjByName(PulseGenerator.NAME);
            if isempty(pg); throwBaseObjException(PulseGenerator.Name); end
            pg.sequence = S;
            pg.repeats = obj.repeats;
            seqTime = pg.sequence.duration * 1e-6; % Multiplication in 1e-6 is for converting usecs to secs.
            
            % Set Frequency Generator
            fg = getObjByName(obj.freqGenName);
            if isempty(fg); throwBaseObjException(obj.freqGenName); end
            fg.frequency = obj.frequency;
            fg.amplitude = BooleanHelper.ifTrueElse(obj.isWithMW, obj.amplitude, fg.minAmpl);
            
            % Set parameter, for saving
            obj.mCurrentXAxisParam.value = obj.detectionDuration;
            if obj.isScanLaserOnDelay
                obj.mCurrentYAxisParam.value = obj.laserOnset;
            else
                obj.mCurrentYAxisParam.value = [];
            end
            
            % Initialize SPCM
            numScans = 2*obj.repeats;
            obj.timeout = 10 * numScans * seqTime;       % Some multiple of the actual duration
            spcm = getObjByName(Spcm.NAME);
            if isempty(spcm); throwBaseObjException(Spcm.Name); end
            spcm.setSPCMEnable(true);
            spcm.prepareExperimentCount(numScans, obj.timeout);
            
            obj.changeFlag = false;     % All devices have been set, according to the ExpParams
        end
        
        function perform(obj)
            %%% Initialization
            
            % Devices (+ Tracker)
            pg = getObjByName(PulseGenerator.NAME);
            seq = pg.sequence;
            spcm = getObjByName(Spcm.NAME);
            tracker = getObjByName(Tracker.NAME);
                if isempty(tracker); throwBaseObjException(Tracker.NAME); end
            
            % Some magic numbers
            maxLastDelay = obj.mwOffDelay + max(obj.detectionDuration) + max(obj.laserOnset);
            len = 2;    % 1 for measurement and 1 for reference
            sig = zeros(1, len);   % allocate memory
            
            %%% Run - Go over all parameter space, in random order
            for t = randperm(length(obj.detectionDuration))
                for u = randperm(length(obj.laserOnset))
                    success = false;
                    for trial = 1 : 5
                        try
                            seq.change('detection', 'duration', obj.detectionDuration(t));
                            seq.change('onset', 'duration', obj.laserOnset(u));
                            if obj.constantTime
                                seq.change('lastDelay', 'duration', ...
                                    maxLastDelay - obj.detectionDuration(t) - obj.laserOnset(u));
                            end
                            
                            data = obj.getRawData(pg, spcm);
                            dur = [obj.detectionDuration(t), obj.referenceDetectionDuration];
                            [sig(1:2), d] = obj.processData(data, dur);
                            sterr = d(2);   % reference std. err.
                            
                            obj.signal(:, u, t, obj.currIter) = sig;
                            
                            if obj.isTracking
                                isTrackingNeeded = tracker.compareReference(...
                                    sig(2), sterr, ...
                                    Tracker.REFERENCE_TYPE_KCPS, obj.trackThreshhold);
                                if isTrackingNeeded
                                    tracker.trackUsing(TrackablePosition.NAME)
                                end
                            end
                            success = true;     % Since we got till here
                            break;
                        catch err
                            warning(err.message);
                            fprintf('Experiment failed at trial %d, attempting again.\n', trial);
                            try
                                % Maybe we need to manually clear the resources
                                spcm.stopGatedCount;
                            catch
                                % But maybe we don't, and that's perfectly ok.
                            end
                        end
                    end
                    if ~success
                        break
                    end
                end
            end
            
            % Saving results in the Experiment parameters
            S1 = squeeze(obj.signal(1, :, :, 1:obj.currIter));
            S2 = squeeze(obj.signal(2, :, :, 1:obj.currIter));
            
            if obj.currIter == 1
                % Nothing to calculate the mean over
                obj.signalParam.value = S1./S2;
            else
                if obj.isScanLaserOnDelay
                    % This changes the dimensions of the signal
                    obj.signalParam.value = mean(S1./S2, 3);
                else
                    obj.signalParam.value = mean(S1./S2, 2);
                end
            end
            
            obj.signalParam2.value = [];
        end
        
        function wrapUp(obj) %#ok<MANU>
            % Things that need to happen when the experiment is done; a
            % counterpart for obj.prepare.
            % In the future, it will also analyze results and fit from it
            % the coherence time.
            
            spcm = getObjByName(Spcm.NAME);
            spcm.setSPCMEnable(false);
        end
        
        function dataParam = alternateSignal(obj)
            % Returns alternate view ("normalized") of the data, as an
            % ExpParam, if possible. If not, it returns an empty variable.
            
            dataParam = ExpResultDoubleVector('SNR', [], '', obj.NAME);

            signal = obj.signalParam.value;
            stdev = obj.signalParam2.value;
            dataParam.value = signal./stdev;
        end
    end
    
    %% (Static) helper functions
    methods (Static)
        function name = getFgName(FG)
            % Get name of relevant frequency generator (if there is only
            % one; otherwise, we can't tell which one to use)
            
            if nargin == 0 || isempty(FG)
                % No input -- we take the default FG
                name = FrequencyGenerator.getDefaultFgName;
            elseif ischar(FG)
                FgObj = getObjByName(FG);
                if isempty(FgObj)
                    throwBaseObjException(FG)
                else
                    name = FG;
                end
            elseif isa(FG, 'FrequencyGenerator')
                name = FG.name;
            else
                EventStation.anonymousError('Sorry, but a %s is not a Frequency Generator...', class(FG))
            end
        end
    end
    
end

