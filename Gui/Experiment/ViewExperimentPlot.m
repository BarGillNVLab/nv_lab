classdef ViewExperimentPlot < ViewVBox & EventListener
    %VIEWEXPERIMENTPLOT GUI showing results and progress of an Experiment
    
    properties (Access = private)
        expName
        nDim = 1;   % data is 1D 99% of the time. Can be overridden
        isPlotAlternate = false;
        
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
                'OuterPosition', [-0.05 0 1.13 1]);
            obj.progressbarAverages = progressbar(fig, 0, 'Starting experiment. Please wait.');
            
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
            obj.isPlotAlternate = event.NewValue.UserData;
            obj.plot;
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
        
        %%% Plotting %%%
        function plot(obj)
            % Check whether we have anything to plot
            exp = getExpByName(obj.expName);
            if obj.isPlotAlternate
                data = exp.alternateSignal().value;
            else
                data = exp.signalParam.value;
            end

            if isempty(data) || all(isnan(data))
                % Default plot
                firstAxisVector = AxesHelper.DEFAULT_X;
                data = AxesHelper.DEFAULT_Y;
            else
                % First plot
                firstAxisVector = exp.mCurrentXAxisParam.value;
            end
            
            if isempty(obj.vAxes.Children)
                % Nothing is plotted yet
                bottomLabel = exp.mCurrentXAxisParam.label;
                leftLabel = exp.signalParam.label;
                AxesHelper.fill(obj.vAxes, data, obj.nDim, ...
                    firstAxisVector, [], bottomLabel, leftLabel);
                
                % Maybe this experiment shows more than one x/y-axis
                if ~isnan(exp.topParam)
                    AxesHelper.addAxisAcross(obj.vAxes, 'x', ...
                        exp.topParam.value, ...
                        exp.topParam.label)
                end
                if ~isnan(exp.rightParam)
                    AxesHelper.addAxisAcross(obj.vAxes, 'y', ...
                        exp.rightParam.value, ...
                        exp.rightParam.label)
                end
            else
                AxesHelper.update(obj.vAxes, data, obj.nDim, firstAxisVector)
            end
            
            if isa(exp.signalParam2, 'ExpParameter') && ~isempty(exp.signalParam2.value) ...
                % If there is more than one Y axis parameter, we want to
                % plot it above the first one,
                if ~obj.isPlotAlternate
                    % unless We are in alternative display mode.
                    data = exp.signalParam2.value;
                    AxesHelper.add(obj.vAxes, data, firstAxisVector)
                end
                obj.radioAlterDisplay.Enable = BooleanHelper.boolToOnOff(~isempty(exp.alternateSignal));
                    % ^ We can switch to the alternate display mode only if
                    % there is anything to show there.
            else
                % We can't show an alternate display, since there is only one signal
                obj.radioAlterDisplay.Enable = 'off';
            end
            
            
            % Refresh Progress bar
            nDone = exp.currIter;  % The number of the current iteration is also the number of iterations done
            frac = nDone / exp.averages;
            string = sprintf('%d of %d averages (%.2f%%) done', nDone, exp.averages, frac*100);
            progressbar(obj.progressbarAverages, frac, string);

        end
        
        function refresh(obj)
            exp = getExpByName(obj.expName);
            if ~exp.restartFlag
                obj.btnStartStop.startString = 'Resume';
            else
                obj.btnStartStop.startString = 'Start';
            end
            obj.btnStartStop.stopString = 'Pause';
            
            obj.btnStartStop.isRunning = ~exp.stopFlag;
        end
        
        function savePlottingImage(obj, folder, filename)
            % TEMPORARY (!!!) function, to save the plot from an experiment
            % as .png and .fig files
            
            %%% Copy axes to an invisible figure
            figureInvis = AxesHelper.copyToNewFigure(obj.vAxes);
            
            %%% Get name for saving
            filename = PathHelper.removeDotSuffix(filename);
            fullpath = PathHelper.joinToFullPath(folder, filename);
            
            %%% Save image (.png)
            fullPathImage = [fullpath '.' ImageScanResult.IMAGE_FILE_SUFFIX];
            saveas(figureInvis, fullPathImage);
            
            %%% Save figure (.fig)
            % The figure is saved as invisible, but we set its creation
            % function to set it as visible
            set(figureInvis, 'CreateFcn', 'set(gcbo, ''Visible'', ''on'')'); % No other methods of specifying the function seemed to work...
            savefig(figureInvis, fullpath)
            
            %%% close the figure
            close(figureInvis);
        end
    end
    
    %% overridden from EventListener
    methods
        % When events happen, this function jumps.
        % event is the event sent from the EventSender
        function onEvent(obj, event)
            if strcmp(event.creator.name, SaveLoadCatExp.NAME) ...
                    && isfield(event.extraInfo, SaveLoad.EVENT_SAVE_SUCCESS_LOCAL_TO_FILE) ...
                    
                folder = event.extraInfo.(SaveLoad.EVENT_FOLDER);
                filename = event.extraInfo.(SaveLoad.EVENT_FILENAME);
                obj.savePlottingImage(folder, filename);
                return
            end
            
            obj.refresh;
            if isfield(event.extraInfo, Experiment.EVENT_DATA_UPDATED) ...
                    || isfield(event.extraInfo, Experiment.EVENT_EXP_RESUMED)
                obj.plot
            end
        end
    end
    
end

