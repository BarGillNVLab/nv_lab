classdef ViewExperimentPlot < ViewVBox & EventListener
    %VIEWEXPERIMENTPLOT GUI showing results and progress of an Experiment
    
    properties (Access = private)
        expName
        
        vAxes
        
        progressbarAverages
        btnStartStop
        radioNormalDisplay
        radioAlterDisplay
        btnEmergencyStop
    end
    
    methods
        
        function obj = ViewExperimentPlot(expName, parent, controller)
            padding = 15;
            spacing = 15;
            obj@ViewVBox(parent, controller, padding, spacing);
            obj@EventListener({expName, SaveLoadCatExp.NAME});
            obj.expName = expName;
            exp = getExpByName(expName);
            
            fig = obj.component;    % for brevity
            obj.vAxes = axes('Parent', uicontainer('Parent', fig), ...
                'NextPlot', 'replacechildren', ...
                'OuterPosition', [-0.05 0 1.13 1]);     % To be plotted on by the Experiment
            obj.progressbarAverages = progressbar(fig, 0, 'Starting experiment. Please wait.');
            axes();  % So as not to accidently overwrite on these axes
            
            hboxControls = uix.HBox('Parent', fig, ...
                'Spacing', 10, 'Padding', 1);
            obj.btnStartStop = ButtonStartStop(hboxControls, 'Start', 'Pause');
                obj.btnStartStop.startCallback = @obj.btnStartCallback;
                obj.btnStartStop.stopCallback  = @obj.btnStopCallback;
            bgDisplayType = uibuttongroup(...
                'Parent', hboxControls, ...
                'Title', 'Display Mode', ...
                'SelectionChangedFcn',@obj.callbackRadioSelection);
                    rbHeight = 15; % "rb" stands for "radio button"
                    rbWidth = 150;
                    padding = 10;

                    obj.radioNormalDisplay = uicontrol(obj.PROP_RADIO{:}, 'Parent', bgDisplayType, ...
                        'String', exp.displayType1, ...
                        'Position', [padding, 2*padding+rbHeight, rbWidth, rbHeight], ...  % [fromLeft, fromBottom, width, height]
                        'UserData', false ... usually, == not normalized
                        );
                    obj.radioAlterDisplay = uicontrol(obj.PROP_RADIO{:}, 'Parent', bgDisplayType, ...
                        'String', exp.displayType2, ...
                        'Position', [padding, padding, rbWidth, rbHeight], ...  % [fromLeft, fromBottom, width, height]
                        'UserData', true ... usually, == normalized
                        );
            hboxControls.Widths = [-1, 200];
            obj.btnEmergencyStop = uicontrol(obj.PROP_BUTTON_BIG_RED{:}, ...
                'Parent', fig, ...
                'String', 'Halt Experiment', ...
                'Callback', @obj.btnEmergencyStopCallback);
                
            fig.Heights = [-1, 40, 80, 40];
            
            obj.height = 500;
            obj.width = 700;
            
            exp.addGraphicAxes(obj.vAxes); % So that experiment could plot on it
            exp.plotResults;
            obj.refresh;
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
        
        function callbackRadioSelection(obj, ~, event)
            exp = getExpByName(obj.expName);
            exp.isPlotAlternate = event.NewValue.UserData;
            exp.plotResults;
            drawnow
        end
        
        function btnEmergencyStopCallback(obj, ~, ~)
            exp = getObjByName(obj.expName);
            if isempty(exp)
                EventStation.anonymousWarning('%s Experiment does not exist!')
                return
            end
            exp.emergencyStop;
        end
        
        %%% Updating display %%%
        function update(obj)
            exp = getObjByName(obj.expName);
            
            % Refresh Progress bar
            nDone = exp.currIter;  % The number of the current iteration is also the number of iterations done
            frac = nDone / exp.averages;
            string = sprintf('%d of %d averages (%.2f%%) done', nDone, exp.averages, frac*100);
            progressbar(obj.progressbarAverages, frac, string);
            
            % Display type
            if isa(exp.signalParam2, 'ExpParameter') && ~isempty(exp.signalParam2.value)
                % We can switch to the alternate display mode only if
                % there is anything to show there.
                obj.radioAlterDisplay.Enable = BooleanHelper.boolToOnOff(~isempty(exp.alternateSignal));
            else
                % We can't show an alternate display, since there is only one signal
                obj.radioAlterDisplay.Enable = 'off';
            end
        end
        
        function refresh(obj)
            % Start/Stop status
            exp = getExpByName(obj.expName);
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
        function onEvent(obj, event)
            obj.refresh;
            if isfield(event.extraInfo, Experiment.EVENT_DATA_UPDATED) ...
                    || isfield(event.extraInfo, Experiment.EVENT_EXP_RESUMED)
                obj.update;
            end
        end
    end
    
end

