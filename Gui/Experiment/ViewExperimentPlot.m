classdef ViewExperimentPlot < ViewVBox & EventListener
    %VIEWEXPERIMENTPLOT Summary of this class goes here
    %   Detailed explanation goes here
    
    properties (Access = private)
        expName
        nDim = 1;   % data is 1D 99% of the time. Can be overridden by subclasses
        
        vAxes
        progressbarAverages
        btnStartStop
    end
    
    methods
        
        function obj = ViewExperimentPlot(expName, parent, controller)
            padding = 15;
            spacing = 15;
            obj@ViewVBox(parent, controller, padding, spacing);
            obj@EventListener(Experiment.NAME);
            obj.expName = expName;
            
            fig = obj.component;    % for brevity
            obj.vAxes = axes('Parent', fig, ...
                'NextPlot', 'replacechildren', ...
                'OuterPosition', [0.1, 0.1, 0.8, 0.8]);
            obj.progressbarAverages = progressbar(fig, 0, 'Starting experiment. Please wait.');
            obj.btnStartStop = ButtonStartStop(fig);
                obj.btnStartStop.startCallback = @obj.btnStartCallback;
                obj.btnStartStop.stopCallback  = @obj.btnStopCallback;
            fig.Heights = [-1, 40, 30];
            
            obj.height = 600;
            obj.width = 800;
            
            obj.refresh;
        end
        
        
        %%% Callbacks %%%
        function btnStopCallback(obj, ~, ~)
            exp = obj.getExperiment;
            exp.pause;
        end
        
        function btnStartCallback(obj, ~, ~)
            exp = obj.getExperiment;
            exp.run;
        end
        
        %%% Plotting %%%
        function plot(obj)
            % Check whether we have anything to plot
            exp = obj.getExperiment;
            data = exp.mCurrentYAxisParam.value;
            
            if isempty(obj.vAxes.Children)
                % Nothing is plotted yet
                if isempty(data) || all(isnan(data))
                    % Default plot
                    firstAxisVector = AxesHelper.DEFAULT_X;
                    data = AxesHelper.DEFAULT_Y;
                else
                    % First plot
                    firstAxisVector = exp.mCurrentXAxisParam.value;
                end
                bottomLabel = exp.mCurrentXAxisParam.label;
                leftLabel = exp.mCurrentYAxisParam.label;
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
                firstAxisVector = exp.mCurrentXAxisParam.value;
                AxesHelper.update(obj.vAxes, data, obj.nDim, firstAxisVector)
            end
            
            if ~isempty(exp.mCurrentYAxisParam2.value)
                % If there is more than one Y axis parameter, we want to
                % plot it above the first one
                data = exp.mCurrentYAxisParam2.value;
                AxesHelper.add(obj.vAxes, data, firstAxisVector)
                
%                 % We now need a legend
%                 label1 = 'signal';
%                 label2 = exp.mCurrentYAxisParam2.label;
            end

        end
        
        
        function refresh(obj)
            exp = obj.getExperiment;
            % Progress bar
            nDone = exp.nIter - 1;     % We are done with the previous n-1 iterations
            frac = nDone / exp.averages;
            string = sprintf('%d of %d averages (%.2f%%) done', nDone, exp.averages, frac*100);
            progressbar(obj.progressbarAverages, frac, string);
            % Button
            obj.btnStartStop.isRunning = ~exp.stopFlag;
        end
        
    end
    
    methods
        function exp = getExperiment(obj)
            if Experiment.current(obj.expName)
                exp = getObjByName(Experiment.NAME);
            else
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
            % We're listening to all experiments, but only care if the
            % experiment is "ours".
            if strcmp(event.creator.EXP_NAME, obj.expName)
                obj.refresh;
                if isfield(event.extraInfo, Experiment.EVENT_DATA_UPDATED)
                    obj.plot
                end
            end
        end
    end
    
end

