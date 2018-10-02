classdef (Abstract) LaserPartAbstract < EventSender
    %LASERABSTRACT Abstract layer above the physics. 
    %   Saves all the matlab info (such as current value, isActive) and
    %   calls events.
    %
    %   Child classes must:
    %   @ assign value to property canSetEnabled
    %   @ assign value to property canSetValue
    %
    %   If needed, Child class should override:
    %   @ setValueRealWorld
    %   @ getValueRealWorld
    %   @ setEnabledRealWorld
    %   @ getEnabledRealWorld
    %
    %   The code is right here for use:
    %-------------------------------------------------------
    %     
    %     %% Overridden from LaserPartAbstract
    %         %%%% These functions call physical objects. Tread with caution! %%%%
    %         methods (Access = protected)
    %             function setValueRealWorld(obj, newValue)
    %                 % Sets the voltage value in physical laser part
    %             end
    %
    %             function value = getValueRealWorld(obj)
    %                 % Gets the voltage value from physical laser part
    %                 value = 100;
    %             end             
    %             
    %             function setEnabledRealWorld(obj, newBool)
    %                 % Sets the physical laser part on (true) or off (false)
    %             end
    %             
    %             function tf = getEnabledRealWorld(obj)
    %                 % Returns whether the physical laser part is on (true) or off (false)
    %                 tf = true;
    %             end
    %         end

    
    properties (Abstract)
        canSetEnabled   % logical
        canSetValue     % logical
    end
    
    properties (Dependent)
        value           % double. If it cannot be changed, it is effectively on full power.
        isEnabled       % logical. If it cannot be changed, it is always on.
    end
    
    properties (SetAccess = protected, Hidden)
        minValue
        maxValue
        units
    end
       
    properties (Access = private)
        calibFunc;      % function handle. Converts from percentage to physical units.
    end
    
    properties (Constant)
        DEFAULT_MIN_VALUE = 0;
        DEFAULT_MAX_VALUE = 100;
        DEFAULT_UNITS = '%';
    end
    
    methods
        %% constructor
        function obj = LaserPartAbstract(name, minVal, maxVal, func, units)
            % Creates an abstract laser part.
            % 
            % Requires at least one parameter, 'name', for the part.
            % 
            % min - double. Minimum value the user can input. Default value is 0.
            % max - double. Maximum value the user can input. Default value is 100.
            % func - function handle. Calibration function.
            % units - string. Units of the value. Default units are '%'.
            obj@EventSender(name);
            addBaseObject(obj);     % so it can be reached by BaseObject.getByName()
            
            if exist('minVal', 'var') && ~isempty(minVal); obj.minValue = minVal;
            else; obj.minValue = obj.DEFAULT_MIN_VALUE; end
            
            if exist('maxVal', 'var') && ~isempty(maxVal); obj.maxValue = maxVal;
            else; obj.maxValue = obj.DEFAULT_MAX_VALUE; end
            
            if exist('calibfunc', 'var') && ~isempty(func); obj.calibFunc = func; 
            else; obj.calibFunc = []; end
            
            if exist('units', 'var') && ~isempty(units); obj.units = units;
            else; obj.units = obj.DEFAULT_UNITS; end
        end
        
        function on(obj)
            obj.isEnabled = true;
        end
        
        function off(obj)
            obj.isEnabled = false;
        end
    end
       
    methods
        %% Setters
        function set.value(obj, newValue)
            %%% Set a new value to the laser
            
            % Error handling
            if ~isnumeric(newValue)
                newValue = str2double(newValue);
                if isnan(newValue)     % Conversion failed
                    obj.sendError('Laser power must be a number');
                end
            elseif ~ValidationHelper.isInBorders(newValue, obj.minValue, obj.maxValue)
                obj.sendError(sprintf('Laser power can''t be set to %d%s: out of limits!\nIgnoring. (limits: [%d, %d])', ...
                    newValue, obj.units, obj.minValue, obj.maxValue));
            end
            
            % Setting value
            if ~isempty(obj.calibFunc)
                % There is a calibration function, so we use it
                newValue = obj.calibFunc(newValue);
            end
            obj.setValueRealWorld(newValue);
            obj.sendEvent(struct('value', newValue));
        end
        
        function set.isEnabled(obj, newValueLogical)
            % Setting the "enabled" state of the laser
            %
            % we want to assert that newValueBool is logical, however
            % islogical would not work, since 0 and 1 are not logical,
            % yet they equal false and true.
            tf = ValidationHelper.isTrueOrFalse(newValueLogical);
            assert(tf, 'Value must be either true or false! Nothing happenned.')
            obj.setEnabledRealWorld(newValueLogical);
            obj.sendEvent(struct('isEnabled', newValueLogical));
        end
        
        %% Getters
        function value = get.value(obj)
            if obj.canSetValue
                value = obj.getValueRealWorld;
            else
                value = 100;
            end
        end
        
        function tf = get.isEnabled(obj)
            if obj.canSetValue
                tf = obj.getEnabledRealWorld;
            else
                tf = true;
            end
        end
        
    end
    
    %% These functions call physical objects. Tread with caution!
    methods (Access = protected)
        function setValueRealWorld(~, ~)
            % Sets the voltage value in physical laser part
        end
        
        function setEnabledRealWorld(~, ~)
            % Sets the physical laser part on (true) or off (false)
        end
        
        function value = getValueRealWorld(~)
            % Gets the voltage value from physical laser part
            value = 100;
        end
        
        function tf = getEnabledRealWorld(~)
            % Returns whether the physical laser part is on (true) or off (false)
            tf = true;
        end
    end
    
end

