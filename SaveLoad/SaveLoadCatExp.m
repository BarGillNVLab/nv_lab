classdef SaveLoadCatExp < SaveLoad & EventListener
    %SAVELOADCATIMAGE Summary of this class goes here
    %   Detailed explanation goes here
    
    properties (Constant)
        NAME = SaveLoad.getInstanceName(Savable.CATEGORY_EXPERIMENTS);
    end
    
    methods
        function obj = SaveLoadCatExp
            obj@SaveLoad(Savable.CATEGORY_EXPERIMENTS);
            obj@EventListener(Experiment.NAME);
        end

    end
    
     %% overridden from EventListener
    methods
        % When events happen, this function jumps.
        % event is the event sent from the EventSender
        function onEvent(obj, event)
            % There are two kinds of relevant events: Scan started and scan
            % ended:
            if isfield(event.extraInfo, Experiment.EVENT_EXP_RESUMED)
                obj.saveParamsToLocalStruct;
                
            elseif isfield(event.extraInfo, Experiment.EVENT_EXP_PAUSED)
                obj.saveResultsToLocalStruct();
            end
        end
    end
    
end

