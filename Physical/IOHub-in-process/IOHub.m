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
    
    properties (Constant, Abstract)
        AVAILABLE_ADDRESSES
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
        function registerChannel(obj, channels)
            %%% Validation %%%
            % Channel data is in correct format
            if ~isa(channels, 'Channel')
                error('Object to be registered is not a channel! Ignoring.')
            end
            
            warnMsg = '';
            % Physical addresses is available
            address = [channels.address];       % Careful! if addresses is are char array, this might break!
            occupiedAdd = obj.channelAddresses; % List of physical addresses already taken
            addressValid = ismember(address, obj.AVAILABLE_ADDRESSES) && ~ismember(address, occupiedAdd);
            if any(~addressValid)
                warnMsg = [warnMsg, 'Some of the channels could not be registered in specified adresses.\n'];
            end
            % Name is not yet taken
            name = {channels.name};
            occupiedName = obj.channelNames;        % list of channel names already taken
            nameValid = ~ismember(name, occupiedName);
            if any(~nameValid)
                warnMsg = [warnMsg, 'Some of the channels could not be registered, since their name already exists in the registrar.'];
            end
            % Let user know what's going on
            tf = addressValid && nameValid;
            if ~any(tf)
                obj.sendError('No channel was registered.')
            elseif any(~tf)
                obj.sendWarning(warnMsg);
            end
            
            %%% Registration %%%
            % Valid channels are added to channel array
            obj.channels = [obj.channels, channels(tf)];
            
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

    end
    
end

