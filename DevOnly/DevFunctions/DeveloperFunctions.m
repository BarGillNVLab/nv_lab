classdef DeveloperFunctions
    %DEVELOPERFUNCTIONS Functions for developers, which have special access
    %to some of the functions, that others don't
    
    properties
    end
    
    methods (Static)
        function map = GetBaseObjectMap
            % For debug mode: gives map of all existing BaseObjects
            
            handle = BaseObject.allObjects;
            map = handle.wrapped;
            
        end
        
        function RemoveBaseObjects
            % For debugging: remove all base objects, without "clear all"
            %                and clear Setup object, so that we can
            %                reinitiate the system
            map = DeveloperFunctions.GetBaseObjectMap();
            k = map.keys;
            
            for i = 1:length(k)
                delete(map(k{i}))
            end
            delete(map)
            delete(Setup.getInstance())
        end
    end
    
end

