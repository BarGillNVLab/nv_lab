classdef ExpRabi < Experiment
    % EXPRABI Rabi Experiment
    
    %%% Runs a normal Rabi with frequency f,
    % a.frequency: the frequency that will be used
    % a.amplitude: the amplituse of the SRS / windfreak, [-5,1] for example will be -5 dBm for the SRS and 1 for the windfreak
    % a.duration: is ~ the duration of each experiment (half the time for
    % MW, and the other half for reference (and cooling))
    % a.repeats: how many repeats for each frequency (in a randomly chosen order)
    % a.averages: how many averages of the whole cycle
    %%% Optional:
    %a.loadExperiment(0:0.002:0.1,2e4,20)
    %%% Run the experiment
    %a.Run;
    %%% Optional:
    %a.plotResults; plot in a new figure window / previously used figure window
    %a.plotResults(10); %will plot in a new figure windon (10)
    
        properties (Constant, Hidden)
        MAX_FREQ = 5e3;   % in MHz (== 5GHz)
        
        MIN_AMPL = -60;   % in dBm
        MAX_AMPL = 3;     % in dBm
        
        MAX_TAU_LENGTH = 1000;
        MIN_TAU = 1e-3;   % in \mus (== 1 ns)
        MAX_TAU = 10;     % in \mus
        
        EXP_NAME = 'Echo';
    end
    
    properties
        frequency   % in MHz
        amplitude   % in dBm
        tau         % in us
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    methods
        function obj = ExpRabi % Defult values go here
            obj@Experiment();
            obj.repeats = 10000;
            obj.averages = 500;
            obj.isTracking = 1; %initialize tracking
            obj.trackThreshhold = 0.7;
            obj.shouldAutosave = false;
            
            obj.frequency = 3029; %in MHz
            obj.amplitude = -10; % in dBm
            obj.tau = 0.002:0.002:0.5; % in us
            obj.detectionDuration = [0.25, 5]; % detection windows, in \mus
            obj.laserInitializationDuration = 10; % laser initialization in pulsed experiments
        end
    end
    
    %% Setters
    methods
        function set.frequency(obj,newVal) % newVal is in MHz
            if ~isscalar(newVal)
                obj.sendError('Rabi Experiment frequency must be scalar')
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
        
        function set.amplitude(obj,newVal) % newVal is in dBm
            if ~isscalar(newVal) || length(newVal) ~= FrequencyGenerator.nAvailable
                obj.sendError('Invalid number of amplitudes for Rabi Experiment! Ignoring.')
            end
            if ~ValidationHelper.isInBorders(newVal ,obj.MIN_AMPL, obj.MAX_AMPL)
                errMsg = sprintf('Amplitude must be between %d and %d!', obj.MIN_AMPL, obj.MAX_AMPL);
                obj.sendError(errMsg);
            end
            % If we got here, then newVal is OK.
            obj.amplitude = newVal;
            obj.changeFlag = true;
        end
        
        function set.tau(obj,newVal) % newVal is in us
            if ~ValidationHelper.isValidVector(newVal, obj.MAX_TAU_LENGTH)
                obj.sendError('In Rabi Experiment, Tau must be a valid vector, and not too long! Ignoring.')
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
                error('Exactly 2 detection duration periods are needed in an Rabi experiment')
            end
        end
        
    end

    methods
        %%%%%
        function LoadExperiment(obj) %X - detection times, in us
            obj.PB.setRepeats(obj.repeats);
            %%% load the experiment
            obj.PB.newSequence;
            if length(obj.detectionDuration) ~= 2
                error('Two detection duration periods are needed in Rabi')
            end
            obj.PB.newSequenceLine('greenLaser', obj.laserOnDelay) % calibration of the laser with SPCM (laser on)
            obj.PB.newSequenceLine({'greenLaser','detector'}, obj.detectionDuration(1)) % Detection
            obj.PB.newSequenceLine({'greenLaser'}, obj.laserInitializationDuration-sum(obj.detectionDuration)) % initialization
            obj.PB.newSequenceLine({'greenLaser','detector'}, obj.detectionDuration(2)) % reference detection
            obj.PB.newSequenceLine('', obj.laserOnDelay+0.5); % calibration of the laser with SPCM (laser off)
            obj.PB.newSequenceLine('MW', obj.tau(1), 'MW') % MW
            obj.PB.newSequenceLine('', obj.lastDeley, 'lastDelay'); % Last delay, making sure the MW is off
            obj.changeFlag = 0;
        end
        
        function Run(obj) %X is the MW duration vector
            try
                obj.LoadExperiment;
                obj.stopFlag = 0;
                obj.SetAmplitude(obj.amplitude(1),1)
                obj.SetFrequency(obj.frequency(1),1)
                numScans = 2*obj.PB.repeats;
                obj.signal = zeros(2,length(obj.tau),obj.averages);
                timeout = 10 * numScans * max(obj.PB.time) *1e-6;
                obj.DAQtask = obj.InitializeExperiment(numScans);
                fprintf('Starting %d averages, each average should take about %.1f seconds.\n', obj.averages, 1e-6*obj.repeats*mean(obj.tau+obj.laserInitializationDuration+obj.lastDeley)*length(obj.tau));
                
                for a = 1:obj.averages
                    for t = randperm(length(obj.tau))
                        obj.PB.changeSequence('MW','duration',obj.tau(t));
                        obj.PB.changeSequence('lastDelay','duration',obj.lastDeley-obj.tau(t));
                        obj.DAQ.startGatedCounting(obj.DAQtask)
                        obj.PB.Run;
                        [s,~] =obj.DAQ.readGatedCounting(obj.DAQtask,numScans,timeout);
                        s = reshape(s,2,length(s)/2);
                        s = mean(s,2).';
                        s = s./(obj.detectionDuration*1e-6)*1e-3;%kcounts per second
                        obj.signal(:,t,a) = s;
                        obj.DAQ.stopTask(obj.DAQtask);
                        
                        tracked = obj.Tracking(s(2));
                        if tracked
                            obj.LoadExperiment
                            obj.DAQtask = obj.InitializeExperiment(numScans);
                        end
                    end
                    fprintf('%s%%\n',num2str(a/obj.averages*100,3))
                    obj.PlotResults(a);
                    drawnow
                    if obj.stopFlag
                        break
                    end
                end
                sprintf('\n');
                obj.CloseExperiment(obj.DAQtask)
            catch err
                try
                    obj.CloseExperiment(obj.DAQtask)
                catch err2
                    warning(err2.message)
                end
                rethrow(err)
            end
        end
        
        function PlotResults(obj,index)
            if isempty(obj.figHandle) || ~isvalid(obj.figHandle)
                figure; 
                obj.figHandle = gca;
                % add apushbutton
                obj.gui.stopButton = uicontrol('Parent',gcf,'Style','pushbutton','String','Stop','Position',[0.0 0.5 100 20],'Visible','on','Callback',@obj.PushBottonCallback);
            end
            if nargin<2
                index = size(obj.signal_,3);
            end
            S1 = squeeze(obj.signal_(1,:,1:index));
            S2 = squeeze(obj.signal_(2,:,1:index));
            
            if index == 1
                S = S1./S2;
            else
                S = mean(S1./S2,2);
            end           
                           
            plot(obj.figHandle, obj.tau, S)
            xlabel('Time (\mus)')
            ylabel('FL (norm)')
        end
        
        function PushBottonCallback(obj,PushButton, EventData)
           obj.stopFlag = 1; 
        end
    end
end