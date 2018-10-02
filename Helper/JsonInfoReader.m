classdef JsonInfoReader
    %JSONINFOREADER Reads the main JsonInfo setup-file
    
    properties (Constant)
        JSON_DIR = 'C:\\lab\\'
        JSON_FILENAME = 'setupInfo.json'
    end
    
    methods (Static)
        function jsonStruct = getJson()
            %%%% Get the json %%%%
            path = [JsonInfoReader.JSON_DIR JsonInfoReader.JSON_FILENAME];
            jsonTxt = fileread(path);
            jsonStruct = jsondecode(jsonTxt);
            
            %%%% Add extra fields %%%%
            if ~isfield(jsonStruct, 'debugMode')
                jsonStruct.debugMode = false;
            end
        end
        
        function setupNum = setupNumber()
            jsonStruct = JsonInfoReader.getJson;
            setupNum = jsonStruct.setupNumber;
            if ~ischar(setupNum)
                setupNum = num2str(setupNum);
            end  
        end
        
        function object = getDefaultObject(listName, defaultNameOptional)
            % Gets from the json an object in a list which has a 'default'
            % property. That is, when we don't know which object from the
            % list we should take, we take the default.
            %
            % listName - char array. Name of the list (e.g. 'stages')
            % defaultNameOptional - char array. If the value is not
            % 'default' (for example, if it's 'greenLaser'), we want to be
            % able to choose it.
            
            if nargin == 1
                % No default name given
                defaultName = 'default';
            else
                defaultName = defaultNameOptional;
            end
            
            if strcmp(listName, 'lasers') && strcmp(defaultName, LaserGate.GREEN_LASER_NAME)
                % This one was designed differently than the
                % others. We can get
                object = getObjByName(LaserGate.GREEN_LASER_NAME);
                % and we're done.
                return
            end
            
            % Otherwise
            jsonStruct = JsonInfoReader.getJson;
            list = jsonStruct.(listName);
            isListACell = iscell(list);
            
            % Initialize search
            isDefault = false(size(list));    % initialize
            
            for i = 1:length(list)
                % Get struct of current object
                if isListACell
                    currentStruct = list{i};
                else
                    currentStruct = list(i);
                end
                
                % Check whether this is THE default object
                if isfield(currentStruct, defaultName)
                    isDefault(i) = true;
                end
            end
            
            % Find out if we have a winner
            nDefault = sum(isDefault);
            switch nDefault
                case 0
                    EventStation.anonymousError('None of the %s is set to be %s! Aborting.', ...
                        listName, defaultName);
                case 1
                    switch listName
                        % We get the object from an objectCell, that should
                        % have already been created
                        case 'stages'
                            objectCell = ClassStage.getStages();
                        case 'frequencyGenerator'
                            objectCell = FrequencyGenerator.getFG();
                    end
                    if length(list) ~= length(objectCell)
                        EventStation.anonymousError('.json file was changed since system setup. Please restart MATLAB.')
                    end
                    
                    % And there it is:
                    object = objectCell{isDefault};
                        
                otherwise
                    EventStation.anonymousError('Too many %s were set as %s! Aborting.', ...
                        listName, defaultName)
            end
            
        end
        
        function [f, minim, maxim] = getFunctionFromLookupTable(path)
            % Creates linear interpolation from lookup table.
            %
            % Input:
            %   filename - string. Path of lookup table file.
            % Output:
            %   f -             function handle. f(value in percentage) = value in physical units
            %   minim, maxim -  double. Limit values for extrapolation
            %
            % Table file is assumed to have two columns:
            %   1st column: value in percentage
            %   2nd column: corresponding value in physical units
            
            % Find correct path
            if ~PathHelper.isFileExists(path)
                % Maybe we have the filename within the 'c:\lab' directory
                appendedPath = PathHelper.joinToFullPath(JsonInfoReader.JSON_DIR, path);
                if ~PathHelper.isFileExists(appendedPath)
                    EventStation.anonymousError('Path ''%s'' for lookup table does not exist!', path)
                end
                path = appendedPath;
            end
                
            
            % Get function
            arr = importdata(path);
            data = arr.data;
            percentage = data(:,1);
            physicalValue = data(:,2);
            f = @(x) interp1(percentage, physicalValue, x);
            
            minim = min(percentage);
            maxim = max(percentage);
        end
    end
    
end

