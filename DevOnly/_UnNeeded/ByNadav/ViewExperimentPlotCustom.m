classdef ViewExperimentPlotCustom < GuiComponent & ViewExperimentPlot
    %VIEWEXPERIMENTPLOTCUSTOM Customizable GUI for plotting Experiments
    
    properties (SetAccess = private)
        plotArea
    end
    
    properties
        vAxes
    end
    
    methods
        %%% Constructor %%%
        function obj = ViewExperimentPlotCustom(expName, parent, controller)
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
            exp.plotResults(obj.vAxes);
        end
    end
    
end

