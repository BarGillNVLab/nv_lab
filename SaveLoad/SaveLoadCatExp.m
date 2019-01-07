classdef SaveLoadCatExp < SaveLoad & EventListener
    %SAVELOADCATIMAGE Summary of this class goes here
    %   Detailed explanation goes here
    
    properties (Constant)
        NAME = SaveLoad.getInstanceName(Savable.CATEGORY_EXPERIMENTS);
    end
    
    methods
        function obj = SaveLoadCatExp
            obj@SaveLoad(Savable.CATEGORY_EXPERIMENTS);
            expNames = Experiment.getExperimentNames;
            obj@EventListener(expNames);
        end
    end
    
     %% overridden from EventListener
    methods
        % When events happen, this function jumps.
        % event is the event sent from the EventSender
        function onEvent(obj, event)
            % There are two kinds of relevant events: when an Experiment
            % (re)starts and when there are new results (so we can save
            % backup).
            
            if isfield(event.extraInfo, Experiment.EVENT_PARAM_CHANGED)
                obj.saveParamsToLocalStruct;
                
            elseif isa(event.creator, 'SpcmCounter')
                % The SPCM counter updates so frequently, we want to treat
                % it seperately, and save backup only when we pause the
                % Counter
                if isfield(event.extraInfo, Experiment.EVENT_EXP_PAUSED)
                    obj.saveResultsToLocalStruct();
                    obj.saveBackup;
                end
            elseif isfield(event.extraInfo, Experiment.EVENT_DATA_UPDATED)
                obj.saveResultsToLocalStruct();
                obj.saveBackup;
            elseif isfield(event.extraInfo, Experiment.EVENT_EXP_PAUSED) ...
                    && event.creator.shouldAutosave
                obj.autoSave;
            end
        end
    end
    
end

