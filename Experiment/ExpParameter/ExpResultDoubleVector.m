classdef (Sealed) ExpResultDoubleVector < ExpParameter
    %EXPRESULTDOUBLEVECTOR 
    
    properties (SetAccess = protected)
        type = ExpParameter.TYPE_RESULT
    end
    
    methods
        function obj = ExpResultDoubleVector(name, value, units, expName)
            obj@ExpParameter(name, value, units, expName);
        end
    end
    
    methods (Static)
        function isOK = validateValue(value)
            % Check if a new value is valid, according to obj.type
            isOK = isnumeric(value) && ~isscalar(value);
        end
    end
    
end

