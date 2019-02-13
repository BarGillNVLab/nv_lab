classdef (Sealed) E3631A_power_supplier < handle
    % controll the E3631A power supplier
    properties (Constant)
        channelNames = {'P6V', 'P25V', 'N25V'}
    end
    
    properties (Access = private)
        id
        com
    end
    
    % Constructor
    methods (Static)
        function obj = getInstance(com)
            persistent localObj
            if isempty(localObj) || ~isvalid(localObj)
                localObj = E3631A_power_supplier(com);
            end
            obj = localObj;
            obj.connect;
        end
    end
    methods (Access = private)
        function obj = E3631A_power_supplier(com)
            if isa(com, 'double')
                com = num2str(com);
            end
            obj.com = com;
            obj.id = serial(sprintf('com%s',obj.com));
        end
    end
    methods
        function connect(obj)
            fclose(obj.id);
            fopen(obj.id);
            for k = 1:length(obj.channelNames)
                obj.setVoltage(obj.channelNames{k},0); %set initial value to 0
            end
            obj.sendCommand('OUTP ON')
        end
        function sendCommand(obj, what)
            fprintf(obj.id, what);
            obj.err;
            %fprintf(obj.id, '*OPC?' ); %See if device is ready
        end
        function err(obj)
            %for k = 1:2
            fprintf(obj.id, 'SYST:ERR?');
            err = fscanf(obj.id);
%            disp(err)
%             if length(err) == 3 && strcmp(err(1),'1')
%                 warning('error ''1'' (??!) recived. Looking for error again')
%                 pause(0.1)
%                 fprintf(obj.id,'SYST:ERR?');
%                 err = fscanf(obj.id);
%             end
            if length(err) ~= 15 || ~strcmp(err(1:13),'+0,"No error"')
                try
                    obj.close
                catch
                    err = [err, '\nDevice connection could not be closed!'];
                end
                error('Error in E3631A power supplier:\n%s', err)
            end
        end
        
        function setVoltage(obj, type, value)
            obj.testPowerLim(type, value)
            obj.sendCommand(sprintf('APPL %s, %.4g', type, value));
        end
        
        function close(obj)
%             try
%                for k = 1:length(obj.channelNames)
%                    obj.sendCommand(sprintf('APPL %s, 0',obj.channelNames{k})); %set initial value to 0
%                end
%                obj.sendCommand('OUTP OFF');
%             catch
%             end
            fclose(obj.id);
        end
    end
    
    methods (Static, Access = private)
        function testPowerLim(type, val)
            switch type
                case 'P6V'
                    if val < 0 || val > 6
                        isError = true;
                    end
                case 'P25V'
                    if val < 0 || val > 25
                        isError = true;
                    end
                case 'N25V'
                    if val > 0 || val < -25
                        isError = true;
                    end
                otherwise
                    error('unknown channel type')
            end
            if isError
                error('Voltage value is out of range')
            end
        end
    end
    
end