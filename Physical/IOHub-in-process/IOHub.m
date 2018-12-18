classdef (Abstract) IOHub < handle
    %IOHUB Abstract superclass for handling input/output hubs
    %
    % Handles registering and controlling data channels for  acquisition
    % (input) and control (ouput)
    %
    
    
    properties
        dummyMode;  	% logical. if set to true nothing will actually be passed
        dummyChannel    % vector of doubles. Saves value of write channels, for dummy mode
        
        channelArray
        % 2D array.         (todo: Better make it an array of Channels)
        % 1st column - channels ('dev/...')
        % 2nd column - channel names ('laser green')
        % 3rd column - channel minimum value. by default it is 0.
        % 4th column - channel maximum value. by default it is 1.
    end
    
    properties (Constant, Hidden)
        IDX_CHANNEL = 1;
        IDX_CHANNEL_NAME = 2;
        IDX_CHANNEL_MIN = 3;
        IDX_CHANNEL_MAX = 4;
        
        DEFAULT_MIN_VOLTAGE = 0;
        DEFAULT_MAX_VOLTAGE = 1;
    end
    
    % Initialization
    methods (Access = protected)
        function obj = IOHub(dummyMode)
            obj@handle;
            if ~exist('dummyMode', 'var')
               dummyMode = false; 
            end
            obj.dummyMode = dummyMode;
            obj.init();
        end
        
        function init(obj)
            obj.channelArray = {};
        end
    end
    
    methods
        function registerChannel(obj, newChannel, newChannelName, minValueOptional, maxValueOptional)
            % We accept also empty values for minValueOptional &
            % maxValueOptional, which allows us to tell the function to
            % use default values for any of the optional variables
            if exist('minValueOptional', 'var') && ~isempty(minValueOptional)
                minValue = minValueOptional;
            else
                minValue = obj.DEFAULT_MIN_VOLTAGE;
            end
            if exist('maxValueOptional', 'var') && ~isempty(maxValueOptional)
                maxValue = maxValueOptional;
            else
                maxValue = obj.DEFAULT_MAX_VOLTAGE;
            end
            
            if ~isempty(obj.channelArray)
                % We want to make sure we are not overwriting an existing
                % channel
                takenIndices = obj.channelArray(1:end, IOHub.IDX_CHANNEL);
                channelAlreadyInIndexes = find(contains(...
                    takenIndices, newChannel));
                if ~isempty(channelAlreadyInIndexes)
                    errorTemplate = 'Can''t assign channel "%s" to "%s", as it has already been taken by "%s"!';
                    channelIndex = channelAlreadyInIndexes(1);
                    channelCapturedName = obj.getChannelNameFromIndex(channelIndex);
                    errorMsg = sprintf(errorTemplate, newChannel, newChannelName, channelCapturedName);
                    obj.sendError(errorMsg);
                end
            end
            
            obj.channelArray{end + 1, IOHub.IDX_CHANNEL} = newChannel;
            obj.channelArray{end, IOHub.IDX_CHANNEL_NAME} = newChannelName;
            obj.channelArray{end, IOHub.IDX_CHANNEL_MIN} = minValue;
            obj.channelArray{end, IOHub.IDX_CHANNEL_MAX} = maxValue;
            
            if obj.dummyMode    % If we are in dummy mode, we want to have default value for value;
                obj.dummyChannel(length(obj.channelArray)) = -1;
            end
        end % func registerChannel
    end
    
    methods (Access = protected)
        function index = getIndexFromChannelOrName(obj, channelOrChannelName)
            if channelOrChannelName(1) == '_'
                % This is a virtual channel. We need to get the index of
                % the real channel (for example, 'ao3' and not '_ao3_vs_aognd')
                channelOrChannelName = regexp(channelOrChannelName, 'ao\d', 'match', 'once');
            end
            
            channelNamesIndexes = find(contains(obj.channelArray(1:end, IOHub.IDX_CHANNEL_NAME), channelOrChannelName));
            if ~isempty(channelNamesIndexes)
                index = channelNamesIndexes(1);
                return;
            end
            
            channelIndexes = find(contains(obj.channelArray(1:end, IOHub.IDX_CHANNEL), channelOrChannelName));
            if ~isempty(channelIndexes)
                index = channelIndexes(1);
                return;
            end
            
            EventStation.anonymousError(...
                '%s couldn''t find either channel or channel name "%s". Have you registered this channel?', ...
                obj.name, channelOrChannelName);
        end
        
        function channelName = getChannelNameFromIndex(obj, index)
            channelName = obj.channelArray{index, IOHub.IDX_CHANNEL_NAME};
        end
        
        function channel = getChannelFromIndex(obj, index)
            channel = obj.channelArray{index, IOHub.IDX_CHANNEL};
        end
        
        function min = getChannelMinimumFromIndex(obj, index)
            min = obj.channelArray{index, IOHub.IDX_CHANNEL_MIN};
            if ~isnumeric(min)
                min = str2double(min);
            end
            if isnan(min)
                min = obj.DEFAULT_MIN_VOLTAGE;
            end
        end
        
        function max = getChannelMaximumFromIndex(obj, index)
            max = obj.channelArray{index, IOHub.IDX_CHANNEL_MAX};
            if ~isnumeric(max)
                max = str2double(max);
            end
            if isnan(max)
                max = obj.DEFAULT_MAX_VOLTAGE;
            end
        end
    end
    
end

