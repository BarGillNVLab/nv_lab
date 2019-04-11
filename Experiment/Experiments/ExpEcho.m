classdef ExpEcho < Experiment
    %EXPECHO Echo experiment
    
    properties (Constant, Hidden)
        MAX_FREQ = 5e3;   % in MHz (== 5GHz)
        
        MIN_AMPL = -60;   % in dBm
        MAX_AMPL = 3;     % in dBm
        
        MAX_TAU_LENGTH = 1000;
        MIN_TAU = 1e-3;   % in \mus (== 1 ns)
        MAX_TAU = 1e3;    % in \mus (== 1 ms)
    end
    
    properties (Constant)
        NAME = 'Echo';
    end
    
    properties
        % Default values (might change during setup)
        frequency = 3029;   %in MHz
        amplitude = -10;    %in dBm
        
        tau = 1:100;        %in us
        halfPiTime = 0.025  %in us
        piTime = 0.05       %in us
        threeHalvesPiTime = 0.075 %in us
        
        
        constantTime = false      % logical
        doubleMeasurement = true  % logical
    end
    
    properties (Access = private)
        freqGenName
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    methods
        function obj = ExpEcho(FG)
            obj@Experiment(ExpEcho.NAME);
            
            % First, get a frequency generator
            if nargin == 0; FG = []; end
            obj.freqGenName = obj.getFgName(FG);
            
            % Set properties inherited from Experiment
            obj.repeats = 1000;
            obj.averages = 2000;
            obj.isTracking = true;   % Initialize tracking
            obj.trackThreshhold = 0.7;
            obj.shouldAutosave = true;
            
            obj.getDelays();
            obj.detectionDuration = [0.25, 5];      % detection windows, in \mus
            obj.laserInitializationDuration = 20;   % laser initialization in pulsed experiments in \mus (??)
            
            obj.mCurrentXAxisParam = ExpParamDoubleVector('Time', [], StringHelper.MICROSEC, obj.NAME);
            obj.signalParam = ExpResultDoubleVector('FL', [], 'normalised', obj.NAME);
            obj.signalParam2 = ExpResultDoubleVector('FL', [], 'normalised', obj.NAME);
        end
    end
    
    %% Setters
    methods
        function set.frequency(obj, newVal) % newVal is in MHz
            if ~isscalar(newVal)
                obj.sendError('Echo Experiment frequency must be scalar')
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
            if ~isscalar(newVal)
                obj.sendError('Echo Experiment amplitude must be scalar')
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
            if ~ValidationHelper.isValidVector(newVal, obj.MAX_TAU_LENGTH)
                obj.sendError('In Echo Experiment, Tau must be a valid vector, and not too long! Ignoring.')
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
        
        function checkDetectionDuration(obj, newVal) %#ok<INUSL>
            % Used in set.detectionDuration. Overriding from superclass
            if length(newVal) ~= 2
                error('Exactly 2 detection duration periods are needed in an Echo experiment')
            end
        end
    end
    
    %% Overridden from Experiment
    methods (Access = protected)
        function reset(obj)
            % (Re)initialize signal matrix and inform user we are starting anew
            measurementlength = 1 + double(obj.doubleMeasurement);   % 1 is single, 2 is double
            obj.signal = zeros(2 * measurementlength, length(obj.tau), obj.averages);
            
            nMeasPerRepeat = length(obj.tau) * (1+obj.doubleMeasurement); % Number of measurements/sequences in each repeat
            obj.resetInternal(nMeasPerRepeat);
        end
        
        function prepare(obj)
            % Initialize devices (SPCM, PulseGenerator, etc.)
            
            checkDetectionDuration(obj, obj.detectionDuration); % The mode might have changed; before running, we check
                                                                % obj.detectionDuration again.
            
            % Sequence
            %%% Useful parameters for what follows
            initDuration = obj.laserInitializationDuration-sum(obj.detectionDuration);
            
            if obj.constantTime
                % The length of the sequence will change when we change
                % tau. To counter that, we add some delay at the end.
                % (mwOffDelay is a property of class Experiment)
                lastDelay = obj.mwOffDelay + 2*max(obj.tau);
            else
                lastDelay = obj.mwOffDelay;
            end
            
            %%% Creating the sequence
            S = Sequence;
            S.addEvent(obj.laserOnDelay,    'greenLaser');                                  % Calibration of the laser with SPCM (laser on)
            S.addEvent(obj.detectionDuration(1),...
                                            {'greenLaser', 'detector'});                    % Detection
            S.addEvent(initDuration,        'greenLaser');                                  % Initialization
            S.addEvent(obj.detectionDuration(2),...
                                            {'greenLaser', 'detector'});                    % Reference detection
            S.addEvent(obj.laserOffDelay);                                                  % Calibration of the laser with SPCM (laser off)
            S.addEvent(obj.halfPiTime,      'MW');                                          % MW
            S.addEvent(obj.tau(end),        '',                         'tau');             % Delay
            S.addEvent(obj.piTime,          'MW');                                          % MW
            S.addEvent(obj.tau(end),        '',                         'tau');             % Delay
            S.addEvent(obj.halfPiTime,      'MW',                       'projectionPulse'); % MW
            S.addEvent(lastDelay,           '',                         'lastDelay');       % Last delay, making sure the MW is off
            
            %%% Send to PulseGenerator
            pg = getObjByName(PulseGenerator.NAME);
            if isempty(pg); throwBaseObjException(PulseGenerator.Name); end
            pg.sequence = S;
            pg.repeats = obj.repeats;
            seqTime = pg.sequence.duration * 1e-6; % Multiplication in 1e-6 is for converting usecs to secs.
            
            % Set Frequency Generator
            fg = getObjByName(obj.freqGenName);
            if isempty(fg); throwBaseObjException(obj.freqGenName); end
            fg.amplitude = obj.amplitude;
            fg.frequency = obj.frequency;
            
            % Set parameter, for saving
            obj.mCurrentXAxisParam.value = 2*obj.tau;
            
            % Initialize SPCM
            numScans = 2*obj.repeats;
            obj.timeout = 15 * numScans * seqTime;       % some multiple of the actual duration
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
                if isempty(tracker); throwBaseObjException(Tracker.Name); end
            
            % Some magic numbers
            maxLastDelay = obj.mwOffDelay + 2 * max(obj.tau);
            len = 2*(1 + double(obj.doubleMeasurement));    % 2 for single, 4 for double
            sig = zeros(1, len);   % allocate memory
            
            %%% Run - Go over all tau's, in random order
            for t = randperm(length(obj.tau))
                success = false;
                for trial = 1 : 2
                    obj.checkEmergencyStop
                    
                    try
                        seq.change('tau', 'duration', obj.tau(t));
                        if obj.constantTime
                            seq.change('lastDelay', 'duration', maxLastDelay - 2*obj.tau(t));
                        end
                        data = obj.getRawData(pg, spcm);
                        [sig(1:2), d] = obj.processData(data);
                        sterr = d(2);   % reference std. err.
                        
                        if obj.doubleMeasurement
                            seq.change('projectionPulse', 'duration', obj.threeHalvesPiTime);
                            data = obj.getRawData(pg, spcm);
                            sig(3:4) = obj.processData(data);
                            seq.change('projectionPulse', 'duration', obj.halfPiTime);
                        end
                        obj.signal(:, t, obj.currIter) = sig;
                        
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
                            spcm.stopExperimentCount;
                        catch
                            % But maybe we don't, and that's perfectly ok.
                        end
                    end
                end
                if ~success
                    break
                end
            end
            
            % Saving results in the Experiment parameters
            S1 = squeeze(obj.signal(1, :, 1:obj.currIter));
            S2 = squeeze(obj.signal(2, :, 1:obj.currIter));
            
            if obj.currIter == 1
                % Nothing to calculate the mean over
                obj.signalParam.value = S1./S2;
            else
                obj.signalParam.value = mean(S1./S2, 2);
            end
            
            if obj.doubleMeasurement
                S3 = squeeze(obj.signal(3, :, 1:obj.currIter));
                S4 = squeeze(obj.signal(4, :, 1:obj.currIter));
                
                
                if obj.currIter ~= 1
                    obj.signalParam2.value = mean(S3./S4,2);
                else
                    % There is nothing to calculate the mean over
                    obj.signalParam2.value = S3./S4;
                end
            else    
                obj.signalParam2.value = [];
            end
        end
        
        function wrapUp(obj)
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
            persistent dat
            if isempty(dat)
                dat = ExpParamDoubleVector('FL', [], 'normalized', obj.NAME);
            end
            signal = obj.signalParam.value;
            background = obj.signalParam2.value;
            
            if isempty(background)
                dat.value = [];
                obj.sendError('Cannot normalize data without double measurement!')
            else
                dat.value = signal./background;
            end
            
            dataParam = dat;
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

