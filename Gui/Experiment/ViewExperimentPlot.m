classdef ViewExperimentPlot < ViewVBox & EventListener
    %VIEWEXPERIMENTPLOT GUI showing results and progress of an Experiment
    
    properties (Access = private)
        expName
        nDim = 1;   % data is 1D 99% of the time. Can be overridden
        isPlotNormalized = false;
        
        vAxes
        progressbarAverages
        btnStartStop
        radioNormalized
        radioUnnormalized
    end
    
    methods
        
        function obj = ViewExperimentPlot(expName, parent, controller)
            padding = 15;
            spacing = 15;
            obj@ViewVBox(parent, controller, padding, spacing);
            obj@EventListener(expName);
            obj.expName = expName;
            
            fig = obj.component;    % for brevity
            obj.vAxes = axes('Parent', fig, ...
                'NextPlot', 'replacechildren', ...
                'OuterPosition', [0.1, 0.1, 0.8, 0.8]);
            obj.progressbarAverages = progressbar(fig, 0, 'Starting experiment. Please wait.');
            
            hboxControls = uix.HBox('Parent', fig, ...
                'Spacing', 10, 'Padding', 1);
            obj.btnStartStop = ButtonStartStop(hboxControls, 'Start', 'Pause');
                obj.btnStartStop.startCallback = @obj.btnStartCallback;
                obj.btnStartStop.stopCallback  = @obj.btnStopCallback;
            bgNormalize = uibuttongroup(...
                'Parent', hboxControls, ...
                'Title', 'Display Mode', ...
                'SelectionChangedFcn',@obj.callbackRadioSelection);
                    rbHeight = 15; % "rb" stands for "radio button"
                    rbWidth = 150;
                    padding = 10;

                    obj.radioUnnormalized = uicontrol(obj.PROP_RADIO{:}, 'Parent', bgNormalize, ...
                        'String', 'Unnormalized', ...
                        'Position', [padding, 2*padding+rbHeight, rbWidth, rbHeight], ...  % [fromLeft, fromBottom, width, height]
                        'UserData', false ... == not normalized
                        );
                    obj.radioNormalized = uicontrol(obj.PROP_RADIO{:}, 'Parent', bgNormalize, ...
                        'String', 'Normalized', ...
                        'Position', [padding, padding, rbWidth, rbHeight], ...  % [fromLeft, fromBottom, width, height]
                        'UserData', true ... == normalized
                        );
            hboxControls.Widths = [-1, 200];
                
            fig.Heights = [-1, 40, 80];
            
            obj.height = 500;
            obj.width = 700;
            
            obj.refresh;
        end
        
        
        %%% Callbacks %%%
        function btnStopCallback(obj, ~, ~)
            try
                exp = getObjByName(obj.expName);
                exp.pause;
                obj.refresh;
            catch
                EventStation.anonymousWarning('There was no Experiment to stop!')
            end
        end
        
        function btnStartCallback(obj, ~, ~)
            try
                exp = getObjByName(obj.expName);
            catch
                
            end
            exp.run;
            obj.refresh;
        end
        
        function callbackRadioSelection(obj, ~, event)
            obj.isPlotNormalized = event.NewValue.UserData;
            obj.plot;
            drawnow
        end
        
        %%% Plotting %%%
        function plot(obj)
            % Check whether we have anything to plot
            exp = getObjByName(obj.expName);
            if obj.isPlotNormalized
                data = exp.normalizedData().value;
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
                if ~obj.isPlotNormalized
                    % unless We are in normalized mode.
                    data = exp.signalParam2.value;
                    AxesHelper.add(obj.vAxes, data, firstAxisVector)
                end
                obj.radioNormalized.Enable = 'on';
            else
                % We can't normalize, since there is only one signal
                obj.radioNormalized.Enable = 'off';
            end
            
            
            % Refresh Progress bar
            nDone = exp.currIter;  % The number of the current iteration is also the number of iterations done
            frac = nDone / exp.averages;
            string = sprintf('%d of %d averages (%.2f%%) done', nDone, exp.averages, frac*100);
            progressbar(obj.progressbarAverages, frac, string);

        end
        
        function refresh(obj)
            exp = getObjByName(obj.expName);
            if exp.pauseFlag
                obj.btnStartStop.startString = 'Resume';
            else
                obj.btnStartStop.startString = 'Start';
            end
            obj.btnStartStop.isRunning = ~exp.stopFlag;
        end
        
    end
    
    methods
        function exp = getExperiment(obj)
            try
                exp = getObjByName(obj.expName);
            catch
                [expNamesCell, expClassNamesCell] = Experiment.getExperimentNames();
                ind = strcmp(obj.expName, expNamesCell); % index of obj.expName in list
                
                % We use @str2func which is superior to @eval, when possible
                className = str2func(expClassNamesCell{ind}); % function handle for the class
                exp = className();
            end
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
                obj.plot
            end
        end
    end
    
end

