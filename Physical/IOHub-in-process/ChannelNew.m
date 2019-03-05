classdef (Abstract) ChannelNew < handle
    %CHANNEL Represents one channel for channel hubs (like Pulse Generators or NiDaq).
    % Data type with all properties common to channels.
    
    properties (SetAccess = private) % To be set on initialization only
        name            % char array. I will answer to this name only.
        address         % index in hub
        onDelay         % double. in microseconds
        offDelay        % double. in microseconds
    end
    
    %%
    methods (Access = protected)
        function obj = ChannelNew(name, address, onDelay, offDelay)
            obj@handle;
            obj.name = name;
            obj.address = address;
            obj.onDelay = onDelay;
            obj.offDelay = offDelay;
        end
    end
    
%     methods
%         function set.value(obj, newVal)
%             switch obj.type
%                 case obj.TYPE_ANALOG
%                     if ~isnumeric(newval)
%                         error('Analog channel value must be numeric!')
%                     elseif (newVal < obj.minimumValue) || (newVal > obj.maximumValue)
%                         error('Analog channel value must be between %d and %d! (requested: %d)', ...
%                             obj.minimumValue, obj.maximumValue, newVal)
%                     end
%                 case obj.TYPE_DIGITAL
%                     if ~ValidationHelper.isTrueOrFalse(newVal)
%                         error('Digital channel value must be convertible to logical!')
%                     end
%             end
%             
%             % newVal passed validation, so in it goes:
%             obj.valuePrivate = newVal;
%         end
%         
%         function val = get.value(obj)
%             val = obj.valuePrivate;
%         end
%         
%         function tf = isDigital(obj)
%             tf = strcmp(obj.type, obj.TYPE_DIGITAL);
%         end
%         function tf = isAnalog(obj)
%             tf = strcmp(obj.type, obj.TYPE_ANALOG);
%         end
%     end
    
end

