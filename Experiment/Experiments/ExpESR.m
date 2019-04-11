classdef ExpESR < Experiment
    %EXPESR ESR (electron spin resonance) Experiment
    
    properties (Constant, Hidden)
        MAX_FREQ_LENGTH = 1e3;
        MIN_FREQ = 0;   % in MHz
        MAX_FREQ = 5e3; % in MHz
        
        MIN_AMPL = -60; % in dBm
        MAX_AMPL = 3;   % in dBm
    end
    
    properties (Constant)
        NAME = 'ESR'
        
        ZERO_FIELD_SPLITTING = 2.87e3     % in Mhz
    end
    
    properties
        frequency           % double. in MHz
        mirrorSweepAround   % double. in MHz
        amplitude           % double. in dBm
        
        mode                % string. Either 'CW' or 'pulsed' 
                            %       ('pulsed is to be implemented in the future, if needed)
        nChannels           % int. Must be <= the number of FGs in the system
        
        halfPiTime          %in us. For pulsed ESR.
        piTime              %in us. For pulsed ESR.
        threeHalvesPiTime   %in us. For pulsed ESR.
    end
    
    properties (Access = private)
        freqMirrored        % set in private function
    end
    
    methods
        
        function obj = ExpESR
            obj@Experiment(ExpESR.NAME);
            
            obj.repeats = 20;
            obj.averages = 10;
            obj.isTracking = true;   % Initialize tracking
            obj.trackThreshhold = 0.7;
            obj.shouldAutosave = true;
            
            obj.frequency = obj.ZERO_FIELD_SPLITTING + (-100 : 1 : 100);     %in MHz
            obj.amplitude = -30;        % dBm
            obj.mode = 'CW';            % Can only be 'CW' for now.
            obj.nChannels = 1;          % two channels can be added....
            
            obj.getDelays();
            obj.detectionDuration = 500;
            
            obj.mirrorSweepAround = []; % Use this for a single frequency range
            obj.freqMirrored = obj.mirrorFrequency;
            
            obj.displayType1 = 'Normalized';
            obj.displayType2 = '-';
            
            obj.mCurrentXAxisParam = ExpParamDoubleVector('Frequency', [], 'MHz', obj.NAME);
            obj.signalParam = ExpResultDoubleVector('FL', [], 'normalised', obj.NAME);
            obj.signalParam2 = ExpResultDoubleVector('FL', [], 'normalised', obj.NAME);
        end
    end
    
    %% Setters
    methods
        function set.frequency(obj ,newVal)	% newVal in microsec
            if ~ValidationHelper.isValidVector(newVal, obj.MAX_FREQ_LENGTH)
                obj.sendError('In ESR Experiment, frequency must be a valid vector, and not too long! Ignoring.')
            end
            if ~ValidationHelper.isInBorders(newVal, obj.MIN_FREQ, obj.MAX_FREQ)
                errMsg = sprintf('All frequencies must be between %d and %d!', obj.MIN_FREQ, obj.MAX_FREQ);
                obj.sendError(errMsg);
            end
            % If we got here, then newVal is OK.
            obj.frequency = newVal;
            obj.changeFlag = true;
        end
        
        function set.amplitude(obj, newVal) % newVal is in dBm
            if ~isscalar(newVal) || length(newVal) ~= FrequencyGenerator.nAvailable
                obj.sendError('Invalid number of amplitudes for ESR Experiment! Ignoring.')
            end
            if ~ValidationHelper.isInBorders(newVal ,obj.MIN_AMPL, obj.MAX_AMPL)
                errMsg = sprintf('Amplitude must be between %d and %d!', obj.MIN_AMPL, obj.MAX_AMPL);
                obj.sendError(errMsg);
            end
            % If we got here, then newVal is OK.
            obj.amplitude = newVal;
            obj.changeFlag = true;
        end
        
        function set.nChannels(obj, newVal)
            if ~isscalar(newVal)
                obj.sendError('Number of channels in ESR must be scalar!')
            end
            if ~ValidationHelper.isValuePositiveInteger(newVal)
                obj.sendError('Number of channels in ESR must be a positive integer!')
            end
            if ~ValidationHelper.isInBorders(newVal, 1, FrequencyGenerator.nAvailable)
                obj.sendError('Number of channels in ESR cannot exceed the number of frequency generators!')
            end
            % If we got here, then newVal is OK.
            obj.nChannels = newVal;
            obj.changeFlag = true;
        end
        
        function set.mode(obj, newVal)
            switch lower(newVal)
                case {'cw', 'continuous', 'cont', 'cwesr'}
                    obj.mode = 'CW';
                case {'pulsed','pulse','pulsedesr'}
                    obj.mode = 'pulsed';
                otherwise
                    obj.sendError('Unknown mode! Ignoring.')
            end
            % If we got here, then the mode was changed
            obj.changeFlag = true;
        end
        
        function set.mirrorSweepAround(obj, newVal)
            if ~isempty(newVal)
                % If it is empty, no further checking is needed
                if ~isscalar(newVal)
                    obj.sendError('Mirror frequency must be scalar!')
                end
                if ~ValidationHelper.isInBorders(newVal, obj.MIN_FREQ, obj.MAX_FREQ)
                    errMsg = sprintf('Mirror frequency must be between %d and %d! Requested: %d', ...
                        obj.MIN_FREQ, obj.MAX_FREQ, newVal);
                    obj.sendError(errMsg);
                end
            end
            
            % If we got here, then newVal is OK.
            obj.mirrorSweepAround = newVal;
            obj.changeFlag = true;
        end
        
        function checkDetectionDuration(obj, newVal)
            % Returns an error if property is invalid.
            switch obj.mode
                case 'CW'
                    if length(newVal) ~= 1
                        error('A single detection duration is required in a CW ESR experiment')
                    end
                case 'pulsed'
                    if length(newVal) ~= 2
                        error('Exactly 2 detection duration periods are needed in a pulsed ESR experiment')
                    end
            end
        end
    end
    
    %% Helper functions
    methods
        function f = mirrorFrequency(obj)
            if isempty(obj.mirrorSweepAround)
                f = [];
            else
                % newFrequencies = |mirrorFreq - (oldFrequencies - mirrorFreq)|
                %                = |2 * mirrorFreq - oldFrequencies|
                % or, in proper code:
                freqList = abs(2*obj.mirrorSweepAround - obj.frequency);
                f = unique(freqList);   % Orders from smallest to largest
                f = fliplr(f);          % So that frequencies are paired
            end
        end
    end
    
    %% Overridden from Experiment
    methods (Access = protected)
        function reset(obj)
            % (Re)initialize signal matrix and inform user we are starting anew 
            isSingleMeasurement = (isempty(obj.mirrorSweepAround) || obj.nChannels > 1);
            n = BooleanHelper.ifTrueElse(isSingleMeasurement, 2, 4);
            obj.signal = zeros(n, length(obj.frequency), obj.averages);
            
            nMeasPerRepeat = length(obj.frequency) * n / 2;      % Number of measurements/sequences in each repeat
            obj.resetInternal(nMeasPerRepeat);
        end
        
        function prepare(obj)
            % Initialize devices (SPCM, PulseGenerator, etc.)
            
            % Sequence
            checkDetectionDuration(obj, obj.detectionDuration); % The mode might have changed; before running, we check
                                                                % obj.detectionDuration again.
            %%% Create
            S = Sequence;
            switch obj.mode
                case 'CW'
                    switch obj.nChannels
                        case 1
                            P = Pulse(obj.detectionDuration,   {'MW', 'greenLaser', 'detector'});
                        case 2
                            P = Pulse(obj.detectionDuration,   {'MW', 'MW2', 'greenLaser', 'detector'});
                        otherwise
                            obj.sendError('What should we do here?')
                    end
                    
                    S.addPulse(P);
                    S.addEvent(obj.laserOnDelay,         'greenLaser')
                    S.addEvent(obj.detectionDuration,    {'greenLaser','detector'})
                    S.addEvent(obj.laserOffDelay,        'greenLaser')
                case 'pulsed'
                    initDuration = obj.laserInitializationDuration-sum(obj.detectionDuration);
                    if length(obj.piTime) ~= obj.nChannels
                        obj.sendError('There should be pi pulse time for each MW channel')
                    end
                    
                    S.addEvent(obj.laserOnDelay,         'greenLaser')                  % Calibration of the laser with SPCM (laser on)
                    S.addEvent(obj.detectionDuration(1), {'greenLaser','detector'})     % Detection
                    S.addEvent(initDuration,             'greenLaser')                  % Initialization
                    S.addEvent(obj.detectionDuration(2), {'greenLaser','detector'})     % Reference detection
                    S.addEvent(obj.laserOffDelay);                                      % Calibration of the laser with SPCM (laser off)
                    S.addEvent(obj.piTime(1),            'MW')
                    if obj.nChannels > 1
                        S.addEvent(obj.mwOffDelay(1),    '');
                        S.addEvent(obj.piTime(2),        'MW2')
                    end
                    S.addEvent(obj.mwOffDelay(2),        '');
            end
            
            %%% Send to PulseGenerator
            pg = getObjByName(PulseGenerator.NAME);
            if isempty(pg); throwBaseObjException(PulseGenerator.Name); end
            pg.sequence = S;
            pg.repeats = obj.repeats;
            seqTime = pg.sequence.duration * 1e-6; % Multiplication in 1e-6 is for converting usecs to secs.
            
            % Initialize SPCM
            numScans = 2*obj.repeats;
            obj.timeout = 10 * numScans * seqTime;       % some multiple of the actual duration
            spcm = getObjByName(Spcm.NAME);
            if isempty(spcm); throwBaseObjException(Spcm.Name); end
            spcm.setSPCMEnable(true);
            spcm.prepareExperimentCount(numScans, obj.timeout);

            % Initialize FrequencyGenerator
            fgCell = FrequencyGenerator.getFG();
            fg1 = fgCell{1};
            fg1.connect;
            if obj.nChannels > 1
                fg2 = fgCell{2};
                fg2.connect;
            end
            
            % Set parameter, for saving
            obj.mCurrentXAxisParam.value = obj.frequency;
            
            obj.changeFlag = false;     % All devices have been set, according to the ExpParams
        end
        
        function perform(obj)
            % Initialization
            len = length(obj.frequency);
            f1 = randperm(len);
            f2 = randperm(len);
            
            %%% Devices (+ Tracker)
            pg = getObjByName(PulseGenerator.NAME);
            spcm = getObjByName(Spcm.NAME);
            tracker = getObjByName(Tracker.NAME);
                if isempty(tracker); throwBaseObjException(Tracker.Name); end
            
            fgCell = FrequencyGenerator.getFG();
            fg1 = fgCell{1};
            fg1.amplitude = obj.amplitude(1);
            if obj.nChannels > 1
                fg2 = fgCell{2};
                fg2.amplitude = obj.amplitude(2);
            end
            
            % Some magic numbers
            isSingleMeasurement = (isempty(obj.mirrorSweepAround) || obj.nChannels > 1);
            n = BooleanHelper.ifTrueElse(isSingleMeasurement, 2, 4);
            sig = zeros(1, n);
            
            % Run - Go over all frequencies, in random order
            for k = 1:len
                obj.checkEmergencyStop()
                
                i = f1(k);
                fg1.frequency = obj.frequency(i);
                if obj.nChannels > 1
                    fg2.frequency = obj.freqMirrored(i);
                end
                data = obj.getRawData(pg, spcm);
                [sig(1:2), d] = obj.processData(data);
                sterr = d(2);   % reference std. err.
                
                if obj.nChannels == 1 && ~isempty(obj.mirrorSweepAround) % run another sweep with the same source
                    i = f2(k);
                    fg1.frequency = obj.freqMirrored(i);
                    data = obj.getRawData(pg, spcm);
                    sig(3:4) = obj.processData(data);
                end
                
                obj.signal(:, i, obj.currIter) = sig;
                
                % Add tracking
                if obj.isTracking
                        %%% Patch: for CW, we need to decrease MW power
                        if strcmp(obj.mode, 'CW')
                            didAmplitudeChange = true;
                            fg1.amplitude = obj.amplitude(1) - 1.5;
                        end
                    isTrackingNeeded = tracker.compareReference(sig(2), sterr, Tracker.REFERENCE_TYPE_KCPS, obj.trackThreshhold);
                    if isTrackingNeeded
                        tracker.trackUsing(TrackablePosition.NAME)
                    end
                        % Patch part 2: return to original state
                        if didAmplitudeChange, fg1.amplitude = obj.amplitude(1); end
                end
            end
            
                        
            S1 = squeeze(obj.signal(1, :, 1:obj.currIter));
            S2 = squeeze(obj.signal(2, :, 1:obj.currIter));
            
            if obj.currIter == 1
                % Nothing to calculate the mean over
                obj.signalParam.value = S1./S2;
            else
                obj.signalParam.value = mean(S1./S2, 2);
            end
            
            if isSingleMeasurement
                obj.signalParam2.value = [];
            else
                S3 = squeeze(obj.signal(3, :, 1:obj.currIter));
                S4 = squeeze(obj.signal(4, :, 1:obj.currIter));
                
                if obj.currIter == 1
                    % There is nothing to calculate the mean over
                    YMirror = S3./S4;
                else
                    YMirror = mean(S3./S4,2);
                end
                
                obj.signalParam2.value = flip(YMirror);
            end
        end
        
        function wrapUp(obj)
            % Things that need to happen when the experiment is done; a
            % counterpart for obj.prepare.
            % In the future, it will also analyze results and fit from it
            % the resonance frequency/ies
            
            spcm = getObjByName(Spcm.NAME);
            spcm.setSPCMEnable(false);

            % Disconnect FrequencyGenerator
            fgCell = FrequencyGenerator.getFG();
            fg1 = fgCell{1};
            fg1.disconnect;
            if obj.nChannels > 1
                fg2 = fgCell{2};
                fg2.disconnect;
            end
        end
        
        function dataParam = alternateSignal(obj) %#ok<MANU>
            % Returns alternate view ("normalized") of the data, as an
            % ExpParam, if possible. If not, it returns an empty variable.
            dataParam = [];
        end
    end
    
end

