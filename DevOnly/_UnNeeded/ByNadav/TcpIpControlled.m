classdef TcpIpControlled < handle
    %TCPIPCONTROLLED Object controlled via TCP/IP connection
    % This object behaves similarly to a tcpip object, but adjusted for
    % our purposes
    
    properties (Access = protected, Hidden)
        t                   % tcpip. MATLAB representation of the connection
        commDelay = 0.01    % double. (Default value) time (in seconds) between consecutive commands
    end
    
    properties (Dependent)
        status
        bytesAvailable
    end
    
    properties
        keepConnected = true; % logical. Should this connection stay open. True by default
        
        % Properties of s we want available
        ip
        port
        terminator
    end
    
    properties (Abstract)
        name        % Will be inherited from the specific Base Object it will implement
    end
    
    methods
        function obj = TcpIpControlled(ip, port)
            obj.t = serial(ip, port);
            
            % We want to "inherit" the serial object, but only selected methods & properties
            obj.port = obj.t.RemotePort;
            obj.ip = obj.t.RemoteHost;
            obj.terminator = obj.t.Terminator;
        end
        
        function open(obj)
            try 
                fopen(obj.t);
            catch err
                if strcmp(err.identifier, 'MATLAB:tcpip:fopen:opfailed')
                    % If the device was opened by MATLAB, we can probably
                    % close it, and open a new connection
                    fclose(instrfind('RemoteHost', obj.port));
                    fopen(obj.t);
                else
                    rethrow(err)
                end
            end
        end
        
        function close(obj)
            fclose(obj.s);
        end
        
        function delete(obj)
            if strcmp(obj.status, 'open')
                % Free the instrument for other procceses
                try
                    obj.close;
                catch
                    msg = sprintf('Could not disconnect %s upon deletion!', obj.name);
                    EventStation.anonymousWarning(msg)
                end
            end
            delete(obj.s);
        end
    end
    
    %% Wrapper methods for serial class
    methods
        function sendCommand(obj, command)
            if ~ischar(command)
                EventStation.anonymousError('Command should be a string! Can''t send command to device.')
            end
            
            if ~obj.keepConnected; obj.open; end
            fprintf(obj.s, command);
            pause(obj.commDelay);
            if ~obj.keepConnected; obj.close; end
        end
        
        function string = read(obj, format)
            if ~obj.keepConnected; obj.open; end
            if exist('format', 'var')
                string = fscanf(obj.s, format);
            else % Realy, you should readAll(). But just in case you only want one line...
                string = fscanf(obj.s);
            end
            pause(obj.commDelay);
            if ~obj.keepConnected; obj.close; end
        end
        
        function string = readAll(obj)
            if ~obj.keepConnected; obj.open; end
            string = [];        % init
            while obj.s.BytesAvailable > 1
                % Might have one char, without terminator. Ideally, this should have been 0.
                % In the onefive Katana, it is 1.
                temp = fscanf(obj.s);
                string = [string temp]; %#ok<AGROW>
                pause(obj.commDelay);
            end
            if ~obj.keepConnected; obj.close; end
        end
        
        % One command to rule them all
        function string = query(obj, command, regex)
            % Sends command and empties output before next command --
            % should be used even if output is irrelevant.
            % We can filter out only wanted information, using regular
            % expressions (RegEx, for short), the output will return the
            % tokens specified in the regex.
            obj.sendCommand(command);
            string = obj.readAll;
            if exist('regex', 'var') && ~isempty(string)
                string = regexp(string, regex, 'tokens', 'once');    % returns cell of strings
                if ~isempty(string) % cell2mat can't handle a 0x0 cell array
                    string = cell2mat(string);
                else
                    string = '';
                end
            end
        end
    end
    
    methods % Setters & getters
        % Setters
        function set.port(obj, newPort)
            obj.s.Port = newPort; %#ok<*MCSUP>
            obj.port = newPort;
        end
        function set.baudRate(obj, bRate)
            obj.s.BaudRate = bRate;
            obj.baudRate = bRate;
        end
        function set.dataBits(obj, dBits)
            obj.s.DataBits = dBits;
            obj.dataBits = dBits;
        end
        function set.stopBits(obj, sBits)
            obj.s.StopBits = sBits;
            obj.stopBits = sBits;
        end
        function set.parity(obj, prty)
            obj.s.Parity = prty;
            obj.parity = prty;
        end
        function set.flowControl(obj, fControl)
            obj.s.FlowControl = fControl;
            obj.flowControl = fControl;
        end
        function set.terminator(obj, term)
            obj.s.Terminator = term;
            obj.terminator = term;
        end
        
        
        function set(obj, varargin)
            % Validity of values is not checked here, It should be
            % done by programmer, or obj.s will alert about it.
            set(obj.s, varargin{:});
        end
        
        function set.keepConnected(obj, value)
            assert(islogical(value), 'keepConnected must be logical (true/false)!')
                obj.keepConnected = value;
        end
        
        % Getters
        function status = get.status(obj)
            status = obj.s.Status;
        end
        
        function bytes = get.bytesAvailable(obj)
            bytes = obj.s.BytesAvailable;
        end
    end
    
end

