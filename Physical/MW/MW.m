classdef MW
    %MWGATE 
    
    properties (Constant)
        NEEDED_FIELDS = {'MW', 'I', 'Q'};
    end
    
    methods (Static)
        function create(mwStruct)
            nFields = MW.NEEDED_FIELDS;
            
            missingField = FactoryHelper.usualChecks(mwStruct, nFields);
            if ~isnan(missingField)
                EventStation.anonymousError(...
                    'Can''t initialize Microwave - needed field "%s" was not found in initialization struct!', ...
                    missingField);
            end
            
            for j = 1:length(nFields)
                S = mwStruct.(nFields{j});
                
                switch lower(S.classname)
                    case {'pulsegenerator', 'pulsestreamer', 'pulseblaster'}
                        SwitchPgControlled.create(S.switchChannelName, S);
                    otherwise
                        EventStation.anonymousError(...
                            'Can''t create a %s-class fast switch - unknown classname! Aborting.', ...
                            S.classname);
                end
            end
        end
    end
    
end

