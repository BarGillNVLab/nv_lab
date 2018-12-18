classdef ChannelAnalog < ChannelNew
    %CHANNELDIGITAL Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        minimumValue    % double.
        maximumValue    % double.
    end
    
    methods
        function obj = ChannelAnalog(name, address, minVal, maxVal, delay)
            if nargin == 4
                % No delay given
                delay = 0;
            end
            obj@ChannelNew(name, address, delay)
            obj.minimumValue = minVal;
            obj.maximumValue = maxVal;
        end
    end
    
end

