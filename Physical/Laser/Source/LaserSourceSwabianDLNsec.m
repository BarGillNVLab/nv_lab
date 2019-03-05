classdef LaserSourceSwabianDLNsec < LaserPartAbstract & SerialControlled
    %LASERSOURCESWABIANDLNSEC Swabian LDnsec laser controller, via RS232
    
    properties
        canSetEnabled = true;
        canSetValue = true;
    end
    
    properties (Constant, Hidden)
        %%%% Commands %%%%
        COMMAND_ON = '*ON'
        COMMAND_OFF = '*OFF'
        COMMAND_ON_QUERY = 'ON?'
        
        COMMAND_POWER_FORMAT_SPEC = 'PWR %4.2f'
        COMMAND_POWER_QUERY = 'PWR?'
        
        NEEDED_FIELDS = {'port'};
    end
    
    methods (Access = private)
        % constructor
        function obj = LaserSourceSwabianDLNsec(name, port)
            obj@LaserPartAbstract(name);
            obj@SerialControlled(port);
            
            obj.baudRate = 9600;
            obj.dataBits = 8;
            obj.stopBits = 1;
            obj.parity = 'none';
            obj.flowControl = 'software';
            
            obj.commDelay = 0.05;
            try
                obj.open;
            catch err
                % We can't communicate with the laser, so what's the point?
                obj.delete
                rethrow(err)
            end
        end
    end
       
    methods
        function delete(obj)
            isEnabled = obj.getEnabledRealWorld;
            if isEnabled % We try to turn the laser off, and we tell the user, whatever happens
                try
                    obj.setEnabled(false);
                    msg = sprintf('Turning off %s, upon deletion', obj.name);
                    obj.sendWarning(msg)
                catch err
                    msg = sprintf('Could not turn off %s upon deletion!', obj.name);
                    obj.sendWarning(msg)
                    err2warning(err)
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
            
            % Save value for when laser is turned off
            obj.valueInternal = newValue;
        end
        
        function val = getValueRealWorld(obj)
            isOn = obj.getEnabledRealWorld;
            if isOn
                regex = '(\d+\.\d+)'; % a value of the form ##.###
                val = str2double(obj.query(obj.COMMAND_POWER_QUERY, regex));
            else
                % The laser gives 0 if it is off.
                val = obj.valueInternal;
            end
        end
        
        function val = getEnabledRealWorld(obj)
            str = obj.query(obj.COMMAND_ON_QUERY);
            if isempty(str)
                val = false;
                warning('Cannot Connect with %s', obj.name)
            elseif contains(str, 'DISABLED')
                val = false;
            elseif contains(str, 'ENABLED')
                val = true;
            else
                warning('Problem in query!!')
            end
        end
    end
    
    %% Factory
    methods (Static)
        function obj = create(name, jsonStruct)
            missingField = FactoryHelper.usualChecks(jsonStruct, LaserSourceSwabianDLNsec.NEEDED_FIELDS);
            if ~isnan(missingField)
                EventStation.anonymousError(...
                    'While trying to create a source part for laser "%s", could not find "%s" field. Aborting', ...
                    name, missingField);
            end
            
            port = jsonStruct.port;
            obj = LaserSourceSwabianDLNsec(name, port);
        end
    end
    
end

