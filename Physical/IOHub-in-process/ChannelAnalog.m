classdef ChannelAnalog < ChannelNew
    %CHANNELDIGITAL Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        minimumValue    % double.
        maximumValue    % double.
    end
    
    methods
        function obj = ChannelAnalog(name, address, minVal, maxVal, onDelay, offDelay)
            if nargin == 4
                % No delay given
                onDelay = 0;
                offDelay = 0;
            end
            obj@ChannelNew(name, address, onDelay, offDelay)
            obj.minimumValue = minVal;
            obj.maximumValue = maxVal;
        end
    end
    
end

