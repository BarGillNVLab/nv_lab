classdef ViewExperimentContolProgress < ViewVBox & EventListener
    %VIEWEXPERIMENTCONTOLPROGRESS Summary of this class goes here
    %   Detailed explanation goes here
    
     properties (Access = private)
        expName

        progressbarAverages
        btnStartStop
        btnEmergencyStop
    end
    
    methods
        function obj = ViewExperimentContolProgress(expName, parent, controller)
            padding = 5;
            spacing = 5;
            obj@ViewVBox(parent, controller, padding, spacing);
            obj@EventListener(expName);
            obj.expName = expName;
            
            fig = obj.component; % for brevity
            
            obj.progressbarAverages = progressbar(fig, 0, 'Starting experiment. Please wait.');
            
            obj.btnStartStop = ButtonStartStop(fig, 'Start', 'Pause');
                obj.btnStartStop.startCallback = @obj.btnStartCallback;
                obj.btnStartStop.stopCallback  = @obj.btnStopCallback;
            
            obj.btnEmergencyStop = uicontrol(obj.PROP_BUTTON_BIG_RED{:}, ...
                'Parent', fig, ...
                'String', 'Halt Experiment', ...
                'Callback', @obj.btnEmergencyStopCallback);
            
            fig.Heights = [-3, -2, -4];
            
            obj.height = 150;
        end
        
        %%% Callbacks %%%
        function btnStopCallback(obj, ~, ~)
            exp = getObjByName(obj.expName);
            if isempty(exp)
                EventStation.anonymousWarning('%s Experiment does not exist!')
                return
            end
            exp.pause;
            obj.btnStartStop.stopString = 'Pausing...';
            obj.btnStartStop.isRunning = true;
        end
        
        function btnStartCallback(obj, ~, ~)
            exp = getExpByName(obj.expName);
            exp.run;
            obj.refresh;
        end
        
        function btnEmergencyStopCallback(obj, ~, ~)
            exp = getObjByName(obj.expName);
            if isempty(exp)
                EventStation.anonymousWarning('%s Experiment does not exist!')
                return
            end
            exp.emergencyStop;
        end
        
        function refresh(obj)
            exp = getExpByName(obj.expName);
            
            % Progress bar
            nDone = exp.currIter;  % The number of the current iteration is also the number of iterations done
            frac = nDone / exp.averages;
            string = sprintf('%d of %d averages (%.2f%%) done', nDone, exp.averages, frac*100);
            progressbar(obj.progressbarAverages, frac, string);
            
            % Start/Stop Button
            if ~exp.restartFlag
                obj.btnStartStop.startString = 'Resume';
            else
                obj.btnStartStop.startString = 'Start';
            end
            obj.btnStartStop.stopString = 'Pause';
            
            obj.btnStartStop.isRunning = ~exp.stopFlag;
        end
    end
    
        %% overridden from EventListener
    methods
        % When events happen, this function jumps.
        % event is the event sent from the EventSender
        function onEvent(obj, ~)
            obj.refresh;
        end
    end
end

