classdef HandleHelper
    %HANDLEHELPER Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
    end
    
    methods (Static)
        function bool = isType(handle,typeName)
            bool = ~isempty(handle) && isvalid(handle) &&  handle.Type == typeName;
        end
    end
    
end

