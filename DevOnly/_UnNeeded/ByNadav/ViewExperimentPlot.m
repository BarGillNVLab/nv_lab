classdef (Abstract) ViewExperimentPlot < EventListener % & GuiComponent
    %VIEWEXPERIMENTPLOT GUI showing results and progress of an Experiment.
    %This superclass controls only the basic interaction with the
    %Experiment, but most actions will be handled by subclasses
    
    % All Children need to implement at least one function, @plot(obj), and
    % should call it at the end of the constructor
    
    properties (Abstract, SetAccess = private)
        plotArea    % The region of the view where all plotting is done (as opposed to controls)
        
    end
    properties (Access = protected)
        expName
    end
    
    methods
        
        function obj = ViewExperimentPlot(expName)
            obj@EventListener({expName, SaveLoadCatExp.NAME});
            obj.expName = expName;
        end
        
        function savePlottingImage(obj, folder, filename)
            % TEMPORARY (!!!) function, to save the plot from an experiment
            % as .png and .fig files. Saving should be included in a proper
            % object, and not in a GUI view.
            
            %%% Copy axes to an invisible figure
            figureInvis = AxesHelper.copyToNewFigure(obj.plotArea);
            
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
            if ~strcmp(Experiment.current, obj.expName)
                return
            end
            
            if strcmp(event.creator.name, SaveLoadCatExp.NAME) ...
                    && isfield(event.extraInfo, SaveLoad.EVENT_SAVE_SUCCESS_LOCAL_TO_FILE) ...
                    
                folder = event.extraInfo.(SaveLoad.EVENT_FOLDER);
                filename = event.extraInfo.(SaveLoad.EVENT_FILENAME);
                obj.savePlottingImage(folder, filename);
                return
            end
            
            if isfield(event.extraInfo, Experiment.EVENT_DATA_UPDATED) ...
                    || isfield(event.extraInfo, Experiment.EVENT_EXP_RESUMED)
                obj.plot
            end
        end
    end
    
end

