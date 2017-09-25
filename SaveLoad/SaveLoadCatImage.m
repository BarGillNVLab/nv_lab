classdef SaveLoadCatImage < SaveLoad & EventListener
    %SAVELOADCATIMAGE Summary of this class goes here
    %   Detailed explanation goes here
    
    properties(Constant = true)
        NAME = SaveLoad.getInstanceName(Savable.CATEGORY_IMAGE);
    end
    
    methods
        function obj = SaveLoadCatImage
            obj@SaveLoad(Savable.CATEGORY_IMAGE);
            obj@EventListener(StageScanner.NAME);
        end
    end
    
     %% overridden from EventListener
    methods
        % when event happen, this function jumps.
        % event is the event sent from the EventSender
        function onEvent(obj, event)
            if ~isfield(event.extraInfo, StageScanner.EVENT_SCAN_FINISHED)
                return
            end
            scanParams = event.extraInfo.(StageScanner.PROPERTY_SCAN_PARAMS);
            if scanParams.autoSave
                obj.autoSave;
            end
        end
    end
    
end

