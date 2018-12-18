classdef ChannelDigital < ChannelNew
    %CHANNELDIGITAL Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
    end
    
    methods
        function obj = ChannelDigital(name, address, delay)
            if nargin == 2
                % No delay given
                delay = 0;
            end
            obj@ChannelNew(name, address, delay)
        end
    end
    
end

