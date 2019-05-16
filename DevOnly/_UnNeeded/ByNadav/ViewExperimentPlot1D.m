classdef ViewExperimentPlot1D < ViewVBox & ViewExperimentPlot
    %VIEWEXPERIMENTPLOT1D GUI for plotting Experiments having only one varying parameter
    
    properties (Constant)
        N_DIM = 1;
    end
    
    properties (SetAccess = private)
        plotArea
    end
    
    properties (Access = private)
        isPlotAlternate = false;
        
        vAxes

        radioNormalDisplay
        radioAlterDisplay
    end
    
    methods
        %%% Constructor %%%
        function obj = ViewExperimentPlot1D(expName, parent, controller)
            padding = 3;
            spacing = 3;
            obj@ViewExperimentPlot(expName)
            obj@ViewVBox(parent, controller, padding, spacing);
            
            obj.expName = expName;
            exp = getExpByName(expName);
            
            fig = obj.component;    % for brevity
            obj.plotArea = uicontainer('Parent', fig);
            obj.vAxes = axes('Parent', obj.plotArea, ...
                'NextPlot', 'replacechildren', ...
                'OuterPosition', [-0.05 0 1.13 1]);
            
            bgDisplayType = uibuttongroup(...
                'Parent', fig, ...
                'Title', 'Display Mode', ...
                'SelectionChangedFcn',@obj.callbackRadioSelection);
                    rbHeight = 20; % "rb" stands for "radio button"
                    rbWidth = 150;
                    padding = 5;

                    obj.radioNormalDisplay = uicontrol(obj.PROP_RADIO{:}, 'Parent', bgDisplayType, ...
                        'String', exp.displayType1, ...
                        'Position', [padding, padding, rbWidth, rbHeight], ...  % [fromLeft, fromBottom, width, height]
                        'UserData', false ... usually, == not normalized
                        );
                    obj.radioAlterDisplay = uicontrol(obj.PROP_RADIO{:}, 'Parent', bgDisplayType, ...
                        'String', exp.displayType2, ...
                        'Position', [2*padding+rbWidth, padding, rbWidth, rbHeight], ...  % [fromLeft, fromBottom, width, height]
                        'UserData', true ... usually, == normalized
                        );


            fig.Heights = [-1, 40];
            
            obj.height = 450;
            obj.width = 700;
            
            obj.plot;
        end
        
        %%% Callbacks %%%
        function callbackRadioSelection(obj, ~, event)
            obj.isPlotAlternate = event.NewValue.UserData;
            obj.plot;
            drawnow
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
                AxesHelper.fill(obj.vAxes, data, obj.N_DIM, ...
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
                AxesHelper.update(obj.vAxes, data, obj.N_DIM, firstAxisVector)
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
             
        end
    end
    
end

