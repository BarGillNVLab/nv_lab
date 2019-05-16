classdef ViewExperimentBasic < ViewVBox & EventListener
    %VIEWEXPERIMENTBASIC GUI showing results and progress of an Experiment
    
    properties
        viewPlotBox
        viewPlot
        viewProgress
        
        controller  % We need to save it, so we can create new children when necessary
        expName
    end
    
    methods
        function obj = ViewExperimentBasic(expName, parent, controller)
            padding = 15;
            spacing = 5;
            obj@ViewVBox(parent, controller, padding, spacing);
            obj@EventListener(expName);
            obj.controller = controller;
            obj.expName = expName;
            
            % Create children views
            obj.viewPlotBox = ViewVBox(obj, controller, 0, 0);
            obj.viewPlot = createViewPlot(obj);
            obj.viewProgress = ViewExperimentContolProgress(expName, obj, controller);
            obj.setHeights([-1, obj.viewProgress.height])
            
            % Size of view
            minWidth = max([obj.viewPlot.width, obj.viewProgress.width]);
            minHeight = obj.viewPlot.height + obj.viewProgress.height;
            
            obj.width = minWidth;
            obj.height = minHeight;
        end
        
        function view = createViewPlot(obj)
            % Creates a plotting area, according to the type of data we
            % have in the experiment. Might have more options in the
            % future.
            delete(obj.viewPlot);   % we need to get rid of the now obselete view
            
            exp = getExpByName(obj.expName);
            if isempty(exp.mCurrentYAxisParam.value)
                view = ViewExperimentPlot1D(obj.expName, obj.viewPlotBox, obj.controller);
            else
                view = ViewExperimentPlot2D(obj.expName, obj.viewPlotBox, obj.controller);
            end
        end
    end
    
    
    %% overridden from EventListener
    methods
        % When events happen, this function jumps.
        % event is the event sent from the EventSender
        function onEvent(obj, event)
            if isfield(event.extraInfo, Experiment.EVENT_PARAM_CHANGED)
                obj.viewPlot = createViewPlot(obj);
            end
        end
    end
end

