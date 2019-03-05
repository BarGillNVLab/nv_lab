classdef ChannelDigital < ChannelNew
    %CHANNELDIGITAL Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
    end
    
    methods
        function obj = ChannelDigital(name, address, onDelay, offDelay)
            if nargin == 2
                % No delay given
                onDelay = 0;
                offDelay = 0;
            end
            obj@ChannelNew(name, address, onDelay, offDelay)
        end
    end
    
end

