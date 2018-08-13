classdef LaserSwitchPhysicalFactory
    %LASERSWITCHPHYSICSFACTORY creates the fast switch for a laser
    %   has only one method: createFromStruct()
    
    properties (Constant)
        NEEDED_FIELDS = {'switchChannelName'}
        OPTIONAL_FIELDS = {'delay', 'isEnabled'}
    end
    
    methods (Static)
        function switchPhysicalPart = createFromStruct(name, struct)
            if isempty(struct)
                switchPhysicalPart = [];
                return
            end
            
            missingField = FactoryHelper.usualChecks(struct, LaserSwitchPhysicalFactory.NEEDED_FIELDS);
            if ~isnan(missingField)
                EventStation.anonymousError(...
                    'Trying to create a fast switch for laser "%s", encountered missing field - "%s". Aborting',...
                    name, missingField);
            end
            
            partName = sprintf('%s fast switch', name);
            
            switch lower(struct.classname)
                case {'pulsegenerator', 'pulsestreamer', 'pulseblaster'}
                    % Maybe we need a global delay of the signal, due to
                    % finite speed of signal
                    if isnan(FactoryHelper.usualChecks(struct, {LaserSwitchPhysicalFactory.OPTIONAL_FIELDS{1}}))
                        % usualChecks() returning nan means everything ok
                        switchChannel = Channel.Digital(struct.switchChannelName, struct.switchChannel, struct.delay);
                    else
                        % No delay requested
                        switchChannel = Channel.Digital(struct.switchChannelName, struct.switchChannel);
                    end
                    switchPhysicalPart = SwitchPgControlled(partName, switchChannel);
                otherwise
                    EventStation.anonymousError(...
                        'Can''t create a %s-class fast switch for laser "%s" - unknown classname! Aborting.', ...
                        struct.classname, name);
            end
            % check for optional field "isEnabled" and set it correctly
            if isnan(FactoryHelper.usualChecks(struct, {LaserSwitchPhysicalFactory.OPTIONAL_FIELDS{2}}))
                % usualChecks() returning nan means everything ok
                switchPhysicalPart.isEnabled = struct.isEnabled;
            end
        end
                    
                    
    end
    
end