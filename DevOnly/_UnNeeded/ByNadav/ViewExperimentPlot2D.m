classdef ViewExperimentPlot2D < GuiComponent & ViewExperimentPlot
    %VIEWEXPERIMENTPLOT1D GUI for plotting Experiments having two varying parameter
    
    properties (Constant)
        N_DIM = 2;
    end
    
    properties (SetAccess = private)
        plotArea
    end
    
    properties (Access = private)
        vAxes
    end
    
    methods
        %%% Constructor %%%
        function obj = ViewExperimentPlot2D(expName, parent, controller)
            obj@ViewExperimentPlot(expName)
            obj@GuiComponent(parent, controller);
                        
            % Create and save the plotting area
            cmpnt = uicontainer('Parent', parent.component);
            obj.component = cmpnt;
            obj.plotArea = cmpnt;
            
            obj.vAxes = axes('Parent', obj.plotArea, ...
                'NextPlot', 'replacechildren', ...
                'OuterPosition', [-0.05 0 1.13 1]);
            
            obj.height = 450;
            obj.width = 700;
            
            obj.plot;
        end
        
        %%% Callbacks %%%
        % (Not needed in this class)
        
        %%% Plotting %%%
        function plot(obj)
            % Check whether we have anything to plot
            exp = getExpByName(obj.expName);
            data = exp.signalParam.value;
            
            if isempty(data) || all(isnan(data))
                % Default plot
                xAxisVector = AxesHelper.DEFAULT_X;
                yAxisVector = AxesHelper.DEFAULT_Y;
            else
                % First plot
                xAxisVector = exp.mCurrentXAxisParam.value;
                yAxisVector = exp.mCurrentYAxisParam.value;
            end
            
            if isempty(obj.vAxes.Children)
                % Nothing is plotted yet
                bottomLabel = exp.mCurrentXAxisParam.label;
                leftLabel = exp.mCurrentYAxisParam.label;
                AxesHelper.fill(obj.vAxes, data, obj.N_DIM, ...
                    xAxisVector, yAxisVector, bottomLabel, leftLabel);
                
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
                AxesHelper.update(obj.vAxes, data, obj.N_DIM, ...
                    xAxisVector, yAxisVector)
            end
             
        end
    end
    
end

