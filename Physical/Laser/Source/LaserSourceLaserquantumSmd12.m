classdef LaserSourceLaserquantumSmd12 < LaserPartAbstract & SerialControlled
    %LASERSOURCELASERQUANTUMSMD12 Laser Quantum SMD12 laser controller, via RS232
    
%     incomplete!!!
    
    properties
        canSetEnabled = true;
        canSetValue = true;
    end
    
    properties (Constant)
        %%%% Commands %%%%
        COMMAND_ON = 'ON'
        COMMAND_OFF = 'OFF'
        COMMAND_ON_QUERY = 'STATUS?'
        
        COMMAND_POWER_FORMAT_SPEC = 'POWER=%4.2f'
        COMMAND_POWER_QUERY = 'POWER?'
        
        NEEDED_FIELDS = {'port'};
    end
    
    methods
        % constructor
        function obj = LaserSourceLaserquantumSmd12(name, port)
            obj@LaserPartAbstract(name);
            obj@SerialControlled(port);

            obj.minValue = 0;
            obj.maxValue = 120;
            obj.units = 'mW';
            
            obj.set(...
                'BaudRate', 9600, ... 
                'StopBits', 1, ...
                'Terminator', 'CR');
            obj.commDelay = 0.05;
            try
                obj.open;
            catch err
                % We can't communicate with the laser, so what's the point?
                obj.delete
                rethrow(err)
            end
        end
        
        function delete(obj)
            isEnabled = obj.getEnabledRealWorld;
            if isEnabled % We try to turn the laser off, and we tell the user, whatever happens
                try
                    obj.setEnabled(false);
                    msg = sprintf('Turning off %s, upon deletion', obj.name);
                    obj.sendWarning(msg)
                catch
                    msg = sprintf('Could not turn off %s upon deletion!', obj.name);
                    obj.sendWarning(msg)
                end
            end
        end
    end
    
    %% Interact with physical laser. Be careful!
    methods (Access = protected)
        function setEnabledRealWorld(obj, newBoolValue)
            % Validating value is assumed to have been done
            if newBoolValue
                obj.sendCommand(obj.COMMAND_ON);
            else
                obj.sendCommand(obj.COMMAND_OFF);
            end
        end
        
        function setValueRealWorld(obj, newValue)
            % Validating value is assumed to have been done
            commandPower = sprintf(obj.COMMAND_POWER_FORMAT_SPEC, newValue);
            obj.query(commandPower);
        end
        
        function val = getValueRealWorld(obj)
            regex = 'lp=(\d+\.\d+)\n'; % a number of the form ##.### followed by new-line
            val = str2double(obj.query(obj.COMMAND_POWER_QUERY, regex));
        end
        
        function val = getEnabledRealWorld(obj)
            regex = 'status: ([01])\n';  % either 0 or 1 followed by new-line
            string = obj.query(obj.COMMAND_ON_QUERY, regex);
            switch string
                case '0'
                    val = false;
                case '1'
                    val = true;
                otherwise
                    obj.sendError('Problem in regex!!')
            end
            
            % Clear memory. Needed because of Katana bug
            if obj.bytesAvailable > 1
                obj.readAll;
            end
        end
    end
    
    %% Factory
    methods (Static)
        function obj = create(name, jsonStruct)
            missingField = FactoryHelper.usualChecks(jsonStruct, LaserSourceOnefiveKatana05.NEEDED_FIELDS);
            if ~isnan(missingField)
                EventStation.anonymousError(...
                    'While trying to create an AOM part for laser "%s", could not find "%s" field. Aborting', ...
                    name, missingField);
            end
            
            port = jsonStruct.port;
            obj = LaserSourceLaserquantumSmd12(name, port);
        end
    end
    %%
    % All available commands, obtained by sending the command 'h':
    % Laser Configuration: SER ANREGE Laser
    % 1. Laser emmision Green on/off: leg=0 (off), leg=1 (on), leg? (status)
    % 3. Laser Green Trigger Source Internal/External frequency: ltg=0 (Int), ltg=1 (Ext), ltg? (status)
    % 8. Green laser external trigger Level: ltlg=xx.xxx (float format), ltlg? (status)
    % 9. Store laser configuration Green: lestg
    % 10. Green Laser Set Temperature: 76.000 deg.C; Actual Temperature=75.990 deg.C
    % 11. Setting the Green Laser Temperature: let=xx.xx
    % 42. Repetition rate (frequency) setting green laser: ltg_freq=xxxxxx in Hz, ltg_freq?(status)
    % 43. Laser power value seting over RS232: lp=xx.xx (from 0-10.0), lp?(status)
    % 44. Laser power seting over RS232/Knob on front panel: lps=1(over RS232), lps=0(knob), lps?(status)
    
end

