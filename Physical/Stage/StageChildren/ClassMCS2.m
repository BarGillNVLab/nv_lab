classdef ClassMCS2 < ClassStage
    % Created by Yoav Romach, The Hebrew University, September, 2016
    % Used to control PI Micos stages
    % libfunctionsview('PI') to view functions
    % To query parameter:
    % [~,~,numericOut,stringOut] = SendPICommand(obj, 'PI_qSPA', obj.ID, szAxes, [hex2dec('6B') hex2dec('6B')], zerosVector, '', 0);
    % szAxes and the following three inputs must of vectors of same length.
    % If numeric output is needed, the last parameter must specify the
    % maximum size.
    
    properties (Constant, Access = protected)
        NAME = 'Stage (Coarse) - MCS2'
        VALID_AXES = 'xyz';
        UNITS = 'um'
        
        COMM_DELAY = 0.005; % 5ms delay needed between consecutive commands sent to the controllers.
        
        LIB_DLL_FOLDER = 'C:/?';
        LIB_DLL_FILENAME = '?';
        LIB_H_FOLDER = 'C:/?/';
        LIB_H_FILENAME = '?';
        LIB_ALIAS = 'MCS2';
        
        ERR_STRING = 'You are silly'; % Should be the value of 'SA_CTL_ERROR_NONE'

        POSITIVE_HARD_LIMITS = [8000 8000 8000];    % in um
        NEGATIVE_HARD_LIMITS = [-8000 -8000 -8000]; % in um
        STEP_MINIMUM_SIZE = 0.1                     % in um
        STEP_DEFAULT_SIZE = 10                      % in um
        
        SERIAL_NUM = 'usb:sn:MCS2-00000000'
    end
       
    properties (Access = protected)
        id
        posSoftRangeLimit
        negSoftRangeLimit
        defaultVel
        curPos
        curVel
        forceStop
        scanRunning
    end
    
    properties
        % For scan
        maxScanSize = 9999;
        macroNumberOfPixels = -1;
        macroMacroNumberOfPixels = -1; % number of points per line
        macroNormalScanVector = -1;
        macroScanVector = -1;
        macroNormalScanAxis = -1;
        macroScanAxis = -1;
        macroPixelTime = -1; % time duration at each pixel
        macroScanVelocity = -1;
        macroNormalVelocity = -1;
        macroFixPosition = 0;
        macroIndex = -1; % -1 = not in scan
        
        % NiDaq
        triggerChannel
        digitalPulseTask = -1; % Digital pulse task for scanning
        
        % Tilt
        tiltCorrectionEnable = false
        tiltThetaXZ = 0
        tiltThetaYZ = 0
    end
    
    methods (Access = protected) % Protected Functions
        function obj = ClassMCS2()
            % name - string
            % availableAxes - string. example: "xyz"
            obj@ClassStage(name, availableAxes)
            
            obj.tiltCorrectionEnable = 0;
            obj.tiltThetaXZ = 0;
            obj.tiltThetaYZ = 0;
            
            obj.LoadPiezoLibrary();
            obj.Connect;
        end

        function Connect(obj)
            [obj.id, ~, ~] = obj.SendCommand('SA_CTL_Close', [], obj.SERIAL_NUM, []);
        end
        
        function Delay(obj, seconds) %#ok<INUSL>
            % Pauses for the given seconds.
            delay = tic;
            while toc(delay) < seconds
            end
        end
        
        function CommunicationDelay(obj)
            % Pauses for obj.commDelay seconds.
            obj.Delay(obj.commDelay);
        end
        
        function varargout = SendCommand(obj, command, realAxis, varargin)
            % Send the command to the controller and returns the output.
            % Automatically adds a waiting period before the command is
            % sent.
            % The first returned output from the command is not returned
            % and is treated as a return code. (Checked for errors)
            
            % Try sending command
            returnCode = [];
            tries = 0;
            while ~strcmp(returnCode, obj.ERR_STRING)
                CommunicationDelay(obj);
                [returnCode, varargout{1:nargout}] = calllib(obj.LIB_ALIAS, command, realAxis, varargin{:});
                tries = tries+1;
                
                % Catch errors
                try
                    CheckReturnCode(obj, returnCode);
                catch error
                    if (~exist('commandVariables', 'var'))
                        if (isempty(varargin))
                            commandVariables = '';
                        else
                            tempVarargin = varargin;
                            for i=1:length(varargin)
                                if (isnumeric(varargin{i}))
                                    tempVarargin{i} = num2str(varargin{i});
                                end
                            end
                            commandVariables=sprintf(', %s',tempVarargin{:});
                        end
                    end
                    fprintf('Caught error while executing command %s(%d%s) - ', command, realAxis, commandVariables);
                    switch error.identifier
                        case -999
                        otherwise
                            fprintf('%s\n',error.identifier);
                            titleString = 'Unexpected error';
                            questionString = sprintf('%s\nSending the command again might result in unexpected behavior...', error.message);
                            retryString = 'Retry command';
                            abortString = 'Abort';
                            confirm = questdlg(questionString, titleString, retryString, abortString, abortString);
                            switch confirm
                                case retryString
                                    obj.sendWarning(error.message);
                                case abortString
                                    obj.sendError(error.message);
                                otherwise
                                    obj.sendError(error.message);
                            end
                    end
                    if (tries == 5)
                        fprintf('Error was unresolved after %d tries\n',tries);
                        obj.sendError(error)
                    end
                    triesString = BooleanHelper.ifTrueElse(tries == 1, 'time', 'times');
                    fprintf('Tried %d %s, Trying again...\n', tries, triesString);
                    pause(1);
                end
            end
            
        end
        
        function varargout = SendCommandWithoutReturnCode(obj, command, varargin)
            % Send the command to the controller and returns the output.
            % Automatically adds a waiting period before the command is
            % sent.
            
            % Send command
            obj.CommunicationDelay;
            [varargout{1:nargout}] = calllib(obj.LIB_ALIAS, command, varargin{:});
        end
        
        function CheckReturnCode(obj, returnCode)
            % Checks the returned code, if an error has occured returns the
            % error (as a MATLAB error/exception)
            
            if ~strcmp(returnCode, obj.ERR_STRING)
                errorMessage = SendCommandWithoutReturnCode(obj, 'SA_CTL_GetResultInfo', returnCode);
                errorId = sprintf('MCS2:%s', reutrnCode);
                error(errorId, 'The following error was received while attempting to communicate with MCS2 controller:\n%s Error  - %s',...
                    returnCode, errorMessage);
            end
        end
        
        function LoadPiezoLibrary(obj)
            % Loads the PI MICOS dll file.

            if(~libisloaded(obj.LIB_ALIAS))
                % Only load dll if it wasn't loaded before.
                shrlib = [obj.LIB_DLL_FOLDER, obj.LIB_DLL_FILENAME];
                hfile = [obj.LIB_H_FOLDER, obj.LIB_H_FILENAME];
                
                loadlibrary(shrlib, hfile, 'alias', obj.LIB_ALIAS);
                fprintf('MCS2 library loaded.\n');
            end
        end
        
        function DisconnectController(obj)
            % This function disconnects the controller at the given ID
            SendCommand(obj, 'SA_CTL_Cancel', obj.id);
            SendCommand(obj, 'SA_CTL_Close', obj.id);
            
        end
        
        function axisIndex = GetAxisIndex(obj, phAxis)
            % Converts x,y,z into the corresponding index for this
            % controller; if stage only has 'z' then z is 1.
            phAxis = GetAxis(obj, phAxis);
            CheckAxis(obj, phAxis)
            axisIndex = zeros(size(phAxis));
            for i=1:length(phAxis)
                axisIndex(i) = strfind(obj.VALID_AXES, obj.axesName(phAxis(i)));
                if isempty(axisIndex(i))
                    obj.sendError('Invalid axis')
                end
            end
        end
        
        function [szAxes, zerosVector] = ConvertAxis(obj, phAxis)
            % Returns the corresponding szAxes string needed to
            % communicate with PI controllers that are connected to
            % multiple axes. Also returns a vector containging zeros with
            % the length of the axes.
            % 'phAxis' can be either a specific axis (x,y,z or 1 for x,
            % 2 for y, and 3 for z) or any vectorial combination of them.
            phAxis = GetAxis(obj, phAxis);
            szAxes = num2str(phAxis);
            zerosVector = zeros(1, length(phAxis));
        end
        
        function CheckAxis(obj, phAxis)
            % Checks that the given axis matches the connected stage.
            % 'phAxis' can be either a specific axis (x,y,z or 1 for x,
            % 2 for y, and 3 for z) or any vectorial combination of them.
            phAxis = GetAxis(obj, phAxis);
            if ~isempty(setdiff(phAxis, GetAxis(obj, obj.VALID_AXES)))
                if length(phAxis) > 1
                    string = 'axis is';
                else
                    string = 'axes are';
                end
                obj.sendError(sprintf('%s %s invalid for the %s controller.', upper(obj.axesName(phAxis)), string, obj.controllerModel));
            end
        end
        
        function CheckRefernce(obj, phAxis)
            % Checks whether the given (physical) axis is referenced, 
            % and if not, asks for confirmation to refernce it.
            phAxis = GetAxis(obj, phAxis);
            refernced = IsRefernced(obj, phAxis);
            if ~all(refernced)
                unreferncedAxesNames = obj.axesName(phAxis(refernced==0));
                if isscalar(unreferncedAxesNames)
                    questionStringPart1 = sprintf('WARNING!\n%s axis is unreferenced.\n', unreferncedAxesNames);
                else
                    questionStringPart1 = sprintf('WARNING!\n%s axes are unreferenced.\n', unreferncedAxesNames);
                end
                % Ask for user confirmation
                questionStringPart2 = sprintf('Stages must be referenced before use.\nThis will move the stages.\nPlease make sure the movement will not cause damage to the equipment!');
                questionString = [questionStringPart1 questionStringPart2];
                referenceString = sprintf('Reference');
                referenceCancelString = 'Cancel';
                confirm = questdlg(questionString, 'Referencing Confirmation', referenceString, referenceCancelString, referenceCancelString);
                switch confirm
                    case referenceString
                        Refernce(obj, phAxis)
                    case referenceCancelString
                        obj.sendError(sprintf('Referencing canceled for controller %s: %s', ...
                            obj.controllerModel, unreferncedAxesNames));
                    otherwise
                        obj.sendError(sprintf('Referencing failed for controller %s: %s - No user confirmation was given', ...
                            obj.controllerModel, unreferncedAxesNames));
                end
            end
        end
        
        function refernced = IsRefernced(obj, phAxis)
            % Check reference status for the given axis.
            % 'phAxis' can be either a specific axis (x,y,z or 1 for x, 2 for y
            % and 3 for z) or any vectorial combination of them.
            CheckAxis(obj, phAxis)
            [szAxes, zerosVector] = ConvertAxis(obj, phAxis);
            [~, refernced] = SendPICommand(obj, 'PI_qFRF', obj.ID, szAxes, zerosVector);
        end
        
        function Refernce(obj, phAxis)
            % Reference the given axis.
            % 'phAxis' can be either a specific axis (x,y,z or 1 for x, 2 for y
            % and 3 for z) or any vectorial combination of them.
            CheckAxis(obj, phAxis)
            [szAxes, zerosVector] = ConvertAxis(obj, phAxis);
            SendPICommand(obj, 'PI_FRF', obj.ID, szAxes);
            
            % Check if ready & if referenced succeeded
            WaitFor(obj, 'ControllerReady')
            [~, refernced] = SendPICommand(obj, 'PI_qFRF', obj.ID,szAxes, zerosVector);
            if (~all(refernced))
                obj.sendError(sprintf('Referencing failed for controller %s with ID %d: Reason unknown.', ...
                    obj.controllerModel, obj.ID));
            end
        end
        
        function Connect(obj)
            % Connects to the controller.
            if(obj.ID < 0)
                % Look for USB controller
                USBDescription = obj.FindController(obj.controllerModel);
                
                % Open Connection
                obj.ID = SendPICommandWithoutReturnCode(obj, 'PI_ConnectUSB', USBDescription);
                obj.CheckIDForError(obj.ID, 'USB Controller found but connection attempt failed!');
            end
            fprintf('Connected to controller: %s\n', obj.controllerModel);
        end
        
        function Initialization(obj)
            % Initializes the piezo stages.
            obj.scanRunning = 0;
            
			todo = 'allow opening without reference'
            % Change to closed loop
            ChangeLoopMode(obj, 'Closed')
            
            % Reference
            CheckRefernce(obj, obj.VALID_AXES)
            
            % Physical units check
            for i=1:length(obj.VALID_AXES)
                [szAxes, zerosVector] = ConvertAxis(obj, obj.VALID_AXES(i));
                [~,~,~,axisUnits] = SendPICommand(obj, 'PI_qSPA', obj.ID, szAxes, hex2dec('7000601'), zerosVector, '', 4);
                if ~strcmpi(strtrim(axisUnits), strtrim(obj.units))
                    obj.sendError(sprintf('%s axis - Stage units are in %s, should be%s', ...
                        upper(obj.VALID_AXES(i)), axisUnits, obj.units));
                else
                    fprintf('%s axis - Units are in%s for position and%s/s for velocity.\n', upper(obj.VALID_AXES(i)), obj.units, obj.units);
                end
            end
            
            CheckLimits(obj);
            
            % Set velocity
            SetVelocity(obj, obj.VALID_AXES, zeros(size(obj.VALID_AXES))+obj.defaultVel);
            
            % Update position and velocity
            QueryPos(obj);
            QueryVel(obj);
            for i=1:length(obj.VALID_AXES)
                fprintf('%s axis - Position: %.4f%s, Velocity: %d%s/s.\n', upper(obj.VALID_AXES(i)), obj.curPos(i), obj.units, obj.curVel(i), obj.units);
            end
        end
        
        function CheckLimits(obj)
            % This function checks that the soft and hard limits matches
            % the stage.
            [szAxes, zerosVector] = ConvertAxis(obj, obj.VALID_AXES);
            
            % Physical limit check
            [~, ~, negPhysicalLimitDistance, ~] = SendPICommand(obj, 'PI_qSPA', obj.ID, szAxes, zerosVector+47, zerosVector, '', 0);
            [~, ~, posPhysicalLimitDistance, ~] = SendPICommand(obj, 'PI_qSPA', obj.ID, szAxes, zerosVector+23, zerosVector, '', 0);
            for i=1:length(obj.VALID_AXES)
                if ((negPhysicalLimitDistance(i) ~= -obj.negRangeLimit(i)) || (posPhysicalLimitDistance(i) ~= obj.posRangeLimit(i)))
                    obj.sendError(sprintf(['Physical limits for %s axis are incorrect!\nShould be: %d to %d.\n', ...
                        'Real value: %d to %d.\nMaybe units are incorrect?'],...
                        upper(obj.VALID_AXES(i)), obj.negRangeLimit(i), obj.posRangeLimit(i), ...
                        -negPhysicalLimitDistance(i), posPhysicalLimitDistance(i)))
                else
                    fprintf('%s axis - Physical limits are from %d%s to %d%s.\n', ...
                        upper(obj.VALID_AXES(i)), obj.negRangeLimit(i), obj.units, obj.posRangeLimit(i), obj.units);
                end
            end
            
            % Soft limit check.
            [~, ~, posSoftLimit, ~] = SendPICommand(obj, 'PI_qSPA', obj.ID, szAxes, zerosVector+21, zerosVector, '', 0);
            [~, ~, negSoftLimit, ~] = SendPICommand(obj, 'PI_qSPA', obj.ID, szAxes, zerosVector+48, zerosVector, '', 0);
            for i=1:length(obj.VALID_AXES)
                if ((negSoftLimit(i) ~= obj.negSoftRangeLimit(i)) || (posSoftLimit(i) ~= obj.posSoftRangeLimit(i)))
                    obj.sendError(sprintf(['Soft limits for %s axis are incorrect!\nShould be: %d to %d.\n', ...
                        'Real value: %d to %d.\nMaybe units are incorrect?'], ...
                        upper(obj.VALID_AXES(i)), obj.negSoftRangeLimit(i), obj.posSoftRangeLimit(i), ...
                        negSoftLimit(i), posSoftLimit(i)))
                else
                    fprintf('%s axis - Soft limits are from %.1f%s to %.1f%s.\n', ...
                        upper(obj.VALID_AXES(i)), obj.negSoftRangeLimit(i), obj.units, obj.posSoftRangeLimit(i), obj.units);
                end
            end
        end
        
        function QueryPos(obj)
            % Queries the position and updates the internal variable.
            szAxes = ConvertAxis(obj, obj.VALID_AXES);
            [~,obj.curPos] = SendPICommand(obj, 'PI_qPOS', obj.ID, szAxes, obj.curPos);
        end
        
        function QueryVel(obj)
            % Queries the velocity and updates the internal variable.
            szAxes = ConvertAxis(obj, obj.VALID_AXES);
            [~,obj.curVel] = SendPICommand(obj, 'PI_qVEL', obj.ID, szAxes, obj.curVel);
        end
        
        function WaitFor(obj, what, phAxis)
            % Waits until a specific action, defined by what, is finished.
            % 'phAxis' can be either a specific (physical) axis (x,y,z or 
            % 1 for x, 2 for y and 3 for z), or any vectorial combination
            % of them.
            % Current options for 'what':
            % MovementDone - Waits until movement is done.
            % onTarget - Waits until the stage reaches it's target.
            % ControllerReady - Waits until the controller is ready (Not
            % need for axis)
            % WaveGeneratorDone - Waits unti the wave generator is done.
            if nargin == 3
                CheckAxis(obj, phAxis);
                [szAxes, zeroVector] = ConvertAxis(obj, phAxis);
            end
            timer = tic;
            timeout = 60; % 60 second timeout
            wait = true;
            while wait
                drawnow % Needed in order to get input from GUI
                if obj.forceStop % Checks if the user pressed the Halt Button
                    HaltPrivate(obj, phAxis);
                    break;
                end
                
                % todo: $what options need to be set as constant properties for
                % external methods to invoke
                switch what
                    case 'MovementDone'
                        [~, moving] = SendPICommand(obj, 'PI_IsMoving', obj.ID, szAxes, zeroVector);
                        wait = any(moving);
                    case 'onTarget'
                        [~, onTarget] = SendPICommand(obj, 'PI_qONT', obj.ID, szAxes, zeroVector);
                        wait = ~all(onTarget);
                    case 'ControllerReady'
                        ready = SendPICommand(obj, 'PI_IsControllerReady', obj.ID, 0);
                        wait = ~ready;
                    case 'WaveGeneratorDone'
                        [~, running] = SendPICommand(obj, 'PI_IsGeneratorRunning', obj.ID, [], 1, 1);
                        wait = running;
                    otherwise
                        obj.sendError(sprintf('Wrong Input %s', what));
                end
                
                if (toc(timer) > timeout)
                    obj.sendWarning(sprintf('Warning, timed out while waiting for controller status: "%s"', what));
                    break
                end
            end
        end
        
        function ScanOneDimension(obj, scanAxisVector, nFlat, nOverRun, tPixel, scanAxis)  %#ok<INUSD>
            %%%%%%%%%%%%%% ONE DIMENSIONAL SCAN MACRO %%%%%%%%%%%%%%
            % Does a macro scan for the given axis.
            % Last 2 variables are for 2D scans.
            % scanAxisVector - A vector with the points to scan, points
            % should increase with equal distances between them.
            % nFlat - How many flat points should be in the beginning of the scan.
            % nOveRun - How many extra points should be taken from each.
            % tPixel - Scan time for each pixel (in seconds).
            % scanAxis - The axis to scan (x,y,z or 1 for x, 2 for y and 3
            % for z).
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            obj.sendWarning(sprintf('Scan not implemented for the %s controller.\n', obj.controllerModel));
        end
        
        function PrepareScanInTwoDimensions(obj, macroScanAxisVector, normalScanAxisVector, nFlat, nOverRun, tPixel, macroScanAxis, normalScanAxis)  %#ok<INUSD>
            %%%%%%%%%%%%%% TWO DIMENSIONAL SCAN MACRO %%%%%%%%%%%%%%
            % Does a macro scan for given axes!
            % scanAxisVector1/2 - Vectors with the points to scan, points
            % should increase with equal distances between them.
            % nFlat - How many flat points should be in the beginning of the scan.
            % nOveRun - How many extra points should be taken from each.
            % tPixel - Scan time for each pixel.
            % scanAxis1/2 - The axes to scan (x,y,z or 1 for x, 2 for y and
            % 3 for z).
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            obj.sendWarning(sprintf('Scan not implemented for the %s controller.\n', obj.controllerModel));
        end
        
        function MovePrivate(obj, phAxis, pos)
            % Absolute change in position (pos) of axis (x,y,z or 1 for x,
            % 2 for y and 3 for z).
            % Vectorial axis is possible.
            % Does not check if scan is running.
            % Does not move if HaltStage was triggered.
            % This function is the one used by all internal functions.
            CheckAxis(obj, phAxis)
            
            if obj.forceStop % Doesn't move if forceStop is enabled
                return
            end
            
            if obj.tiltCorrectionEnable
                [phAxis, pos] = TiltCorrection(phAxis, pos);
            end
            
            if ~PointIsInRange(obj, phAxis, pos) % Check that point is in limits
                obj.sendError('Move Command is outside the soft limits');
            end
            
            CheckRefernce(obj, phAxis)
            
            szAxes = ConvertAxis(obj, phAxis);
            
            % Send the move command
            SendPICommand(obj, 'PI_MOV', obj.ID, szAxes, pos);
            
            % Wait for move command to finish
            WaitFor(obj, 'onTarget', phAxis)
        end

        function HaltPrivate(obj, phAxis)
            % Halts the stage.
            SA_CTL_PKEY_MOVE_MODE = 50659463;
            SA_CTL_MOVE_MODE_CL_RELATIVE = 1;
            
            szAxes = ConvertAxis(obj, phAxis);
            for i = 1:length(phAxis)
                obj.SendCommand('SA_CTL_SetProperty_i32', obj.id, szAxes(i), ...
                    SA_CTL_PKEY_MOVE_MODE, SA_CTL_MOVE_MODE_CL_RELATIVE);
                obj.SendCommand('SA_CTL_Move', obj.id, szAxes(i), 0, 0)
            end
            AbortScan(obj)
            obj.sendWarning('Stage Halted!');
        end
        
        function SetVelocityPrivate(obj, phAxis, vel)
            % Absolute change in velocity (vel) of axis (x,y,z or 1 for x,
            % 2 for y and 3 for z).
            % Does not check if scan is running.
            % Vectorial axis is possible.
            SA_CTL_PKEY_MOVE_VELOCITY = 50659369;
            
            CheckAxis(obj, phAxis)
            szAxes = ConvertAxis(obj, phAxis);
            for i = 1:length(phAxes)
                obj.SendCommand('SA_CTL_SetProperty_i64', obj.id, szAxes(i), ...
                    SA_CTL_PKEY_MOVE_VELOCITY, vel(i));
            end
        end
        
        function [phAxis, pos] = TiltCorrection(obj, phAxis, pos)
            % Corrects the movement axis & pos vectors according to the 
            % tilt angles: If x and/or y axes are given, then z also moves
            % according the tilt angles.
            % However, if also or only z axis is given, then no changes
            % occurs.
            % Assumes the stage has all three xyz axes.
            phAxis = GetAxis(obj, phAxis);
            if ~contains(obj.axesName(phAxis), 'z') % Only do something if there is no z axis
                QueryPos(obj);
                pos = [pos, obj.curPos(3)]; % Adds the z position command, start by writing the current position (as the base)
                for i=1:length(phAxis)
                    switch obj.axesName(phAxis)
                        case 'x'
                            dx = pos(i) - obj.curPos(1);
                            pos(end) = pos(end) + dx*tan(obj.tiltThetaXZ*pi/180); % Adds movements according to the angles
                        case 'y'
                            dy = pos(i) - obj.curPos(2);
                            pos(end) = pos(end) + dy*tan(obj.tiltThetaYZ*pi/180); % Adds movements according to the angles
                    end
                end
                phAxis = [phAxis, 3]; % Add Z axis at the end
            end
        end
    end
    
    methods (Access = public)
        function CloseConnection(obj)
            % Closes the connection to the controllers.
            if (obj.ID ~= -1)
                % ID exists, attempt to close
                DisconnectController(obj, obj.ID)
                fprintf('Connection to controller %s closed: ID %d released.\n', obj.controllerModel, obj.ID);
            else
                obj.ForceCloseConnection(obj.controllerModel);
            end
            obj.ID = -1;
        end
        
        function delete(obj)
            obj.CloseConnection;
        end
        
        function Reconnect(obj)
            % Reconnects the controller.
            CloseConnection(obj);
            Connect(obj);
            Initialization(obj);
        end
        
        function ok = PointIsInRange(obj, phAxis, point)
            % Checks if the given point is within the soft (and hard)
            % limits of the given axis (x,y,z or 1 for x, 2 for y and 3 for z).
            % Vectorial axis is possible.
            CheckAxis(obj, phAxis)
            axisIndex = GetAxisIndex(obj, phAxis);
            ok = all((point >= obj.negSoftRangeLimit(axisIndex)) & (point <= obj.posSoftRangeLimit(axisIndex)));
        end
        
        function [negSoftLimit, posSoftLimit] = ReturnLimits(obj, phAxis)
            % Return the soft limits of the given axis (x,y,z or 1 for x,
            % 2 for y and 3 for z).
            % Vectorial axis is possible.
            CheckAxis(obj, phAxis)
            axisIndex = GetAxisIndex(obj, phAxis);
            negSoftLimit = obj.negSoftRangeLimit(axisIndex);
            posSoftLimit = obj.posSoftRangeLimit(axisIndex);
        end
        
        function [negHardLimit, posHardLimit] = ReturnHardLimits(obj, phAxis)
            % Return the hard limits of the given axis (x,y,z or 1 for x,
            % 2 for y and 3 for z).
            % Vectorial axis is possible.
            CheckAxis(obj, phAxis)
            axisIndex = GetAxisIndex(obj, phAxis);
            negHardLimit = obj.negRangeLimit(axisIndex);
            posHardLimit = obj.posRangeLimit(axisIndex);
        end
        
        function SetSoftLimits(obj, phAxis, softLimit, negOrPos)
            % Set the new soft limits:
            % if negOrPos = 0 -> then softLimit = lower soft limit
            % if negOrPos = 1 -> then softLimit = higher soft limit
            % This is because each time this function is called only one of
            % the limits updates
            CheckAxis(obj, phAxis)
            axisIndex = GetAxisIndex(obj, phAxis);
            if ((softLimit >= obj.negRangeLimit(axisIndex)) && (softLimit <= obj.posRangeLimit(axisIndex)))
                if negOrPos == 0
                    obj.negSoftRangeLimit(axisIndex) = softLimit;
                else
                    obj.posSoftRangeLimit(axisIndex) = softLimit;
                end
            else
                obj.sendError(sprintf('Soft limit %.4f is outside of the hard limits %.4f - %.4f', ...
                    softLimit, obj.negRangeLimit(axisIndex), obj.posRangeLimit(axisIndex)))
            end
        end
        
        function pos = Pos(obj, phAxis)
            % Query and return position of axis (x,y,z or 1 for x, 2 for y
            % and 3 for z)
            % Vectorial axis is possible.
            CheckAxis(obj, phAxis)
            QueryPos(obj);
            axisIndex = GetAxisIndex(obj, phAxis);
            pos = obj.curPos(axisIndex);
        end
        
        function vel = Vel(obj, phAxis)
            % Query and return velocity of axis (x,y,z or 1 for x, 2 for y
            % and 3 for z)
            % Vectorial axis is possible.
            CheckAxis(obj, phAxis)
            QueryVel(obj);
            axisIndex = GetAxisIndex(obj, phAxis);
            vel = obj.curVel(axisIndex);
        end
        
        function Move(obj, phAxis, pos)
            % Absolute change in position (pos) of axis (x,y,z or 1 for x,
            % 2 for y and 3 for z).
            % Vectorial axis is possible.
            % Checks that a scan is not currently running and whether
            % HaltStage was triggered.
            if obj.scanRunning
                obj.sendWarning(obj.WARNING_PREVIOUS_SCAN_CANCELLED);
                AbortScan(obj);
            end
            
            if obj.forceStop % Ask for user confirmation if forcestop was triggered
                questionString = sprintf('Stages were forcefully halted!\nAre you sure you want to move?');
                yesString = 'Yes';
                noString = 'No';
                confirm = questdlg(questionString, 'Movement Confirmation', yesString, noString, yesString);
                switch confirm
                    case yesString
                        obj.forceStop = 0;
                    case noString
                        obj.sendWarning('Movement aborted!')
                        return;
                    otherwise
                        obj.sendWarning('Movement aborted!')
                        return;
                end
            end
            
            MovePrivate(obj, phAxis, pos);
        end
        
        function RelativeMove(obj, phAxis, change)
            % Relative change in position (pos) of axis (x,y,z or 1 for x,
            % 2 for y and 3 for z).
            % Vectorial axis is possible.
            if obj.scanRunning
                obj.sendWarning(obj.WARNING_PREVIOUS_SCAN_CANCELLED);
                AbortScan(obj);
            end
            CheckAxis(obj, phAxis)
            QueryPos(obj);
            axisIndex = GetAxisIndex(obj, phAxis);
            Move(obj, phAxis, obj.curPos(axisIndex) + change);
        end
        
        function Halt(obj)
            % Halts all stage movements.
            % This works by setting the parameter below to 1, which is
            % checked inside the "WaitFor" function. When the WaitFor is
            % triggered, is calls an internal function, "HaltPrivate", which
            % immediately sends a halt command to the controller.
            % Afterwards it also tries to abort scan. The reason abort scan
            % happens afterwards is to minimize the the time it takes to
            % send the halt command to the controller.
            % This parameters also denies the "MovePrivate" command from
            % running.
            % It is reset by a normal/relative "Move Command", which will
            % be triggered whenever a new external move or scan command is
            % sent to the stage.
            obj.forceStop = 1;
        end
        
        function SetVelocity(obj, phAxis, vel)
            % Absolute change in velocity (vel) of axis (x,y,z or 1 for x,
            % 2 for y and 3 for z).
            % Vectorial axis is possible.
            if obj.scanRunning
                obj.sendWarning('2D Scan is in progress, previous scan canceled');
                AbortScan(obj);
            end
            
            CheckAxis(obj, phAxis)
            SetVelocityPrivate(obj, phAxis, vel);
        end
        
        function ScanX(obj, x, y, z, nFlat, nOverRun, tPixel)
            %%%%%%%%%%%%%% ONE DIMENSIONAL X SCAN MACRO %%%%%%%%%%%%%%
            % Does a macro scan for x axis.
            % x - A vector with the points to scan, points should have
            % equal distance between them.
            % y/z - The starting points for the other axes.
            % nFlat - How many flat points should be in the beginning of the scan.
            % nOveRun - How many extra points should be taken from each.
            % tPixel - Scan time for each pixel.
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            if obj.scanRunning
                obj.sendWarning('2D Scan is in progress, previous scan canceled');
                AbortScan(obj);
            end
            Move(obj, ['y' 'z'], [y z]);
            ScanOneDimension(obj, x, nFlat, nOverRun, tPixel, 'x');
            QueryPos(obj);
        end
        
        function ScanY(obj, x, y, z, nFlat, nOverRun, tPixel)
            %%%%%%%%%%%%%% ONE DIMENSIONAL Y SCAN MACRO %%%%%%%%%%%%%%
            % Does a macro scan for y axis.
            % y - A vector with the points to scan, points should have
            % equal distance between them.
            % x/z - The starting points for the other axes.
            % nFlat - How many flat points should be in the beginning of the scan.
            % nOveRun - How many extra points should be taken from each.
            % tPixel - Scan time for each pixel.
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            if obj.scanRunning
                obj.sendWarning('2D Scan is in progress, previous scan canceled');
                AbortScan(obj);
            end
            Move(obj, ['x' 'z'], [x z]);
            ScanOneDimension(obj, y, nFlat, nOverRun, tPixel, 'y');
            QueryPos(obj);
        end
        
        function ScanZ(obj, x, y, z, nFlat, nOverRun, tPixel)
            %%%%%%%%%%%%%% ONE DIMENSIONAL Z SCAN MACRO %%%%%%%%%%%%%%
            % Does a macro scan for z axis.
            % z - A vector with the points to scan, points should have
            % equal distance between them.
            % x/y - The starting points for the other axes.
            % nFlat - How many flat points should be in the beginning of the scan.
            % nOveRun - How many extra points should be taken from each.
            % tPixel - Scan time for each pixel.
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            if obj.scanRunning
                obj.sendWarning('2D Scan is in progress, previous scan canceled');
                AbortScan(obj);
            end
            Move(obj, ['x' 'y'], [x y]);
            ScanOneDimension(obj, z, nFlat, nOverRun, tPixel, 'z');
            QueryPos(obj);
        end
        
        function PrepareScanX(obj, x, y, z, nFlat, nOverRun, tPixel) %#ok<INUSD>
        end
        function PrepareScanY(obj, x, y, z, nFlat, nOverRun, tPixel) %#ok<INUSD>
        end
        function PrepareScanZ(obj, x, y, z, nFlat, nOverRun, tPixel) %#ok<INUSD>
        end
        
        function PrepareScanXY(obj, x, y, z, nFlat, nOverRun, tPixel)
            %%%%%%%%%%%%%% TWO DIMENSIONAL XY SCAN MACRO %%%%%%%%%%%%%%
            % Prepare a macro scan for xy axes!
            % Scanning is done by calling 'ScanNextLine'.
            % Aborting via 'AbortScan'.
            % x/y - Vectors with the points to scan, points should have
            % equal distance between them.
            % z - The starting points for the other axis.
            % nFlat - How many flat points should be in the beginning of the scan.
            % nOveRun - How many extra points should be taken from each.
            % tPixel - Scan time for each pixel.
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            if obj.scanRunning
                obj.sendWarning('2D Scan is in progress, previous scan canceled');
                AbortScan(obj);
            end
            Move(obj, 'z', z);
            PrepareScanInTwoDimensions(obj, x, y, nFlat, nOverRun, tPixel, 'x', 'y');
            QueryPos(obj);
        end
        
        function PrepareScanXZ(obj, x, y, z, nFlat, nOverRun, tPixel)
            %%%%%%%%%%%%%% TWO DIMENSIONAL XZ SCAN MACRO %%%%%%%%%%%%%%
            % Prepare a macro scan for xz axes!
            % Scanning is done by calling 'ScanNextLine'.
            % Aborting via 'AbortScan'.
            % x/z - Vectors with the points to scan, points should have
            % equal distance between them.
            % y - The starting points for the other axis.
            % nFlat - How many flat points should be in the beginning of the scan.
            % nOveRun - How many extra points should be taken from each.
            % tPixel - Scan time for each pixel.
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            if obj.scanRunning
                obj.sendWarning('2D Scan is in progress, previous scan canceled');
                AbortScan(obj);
            end
            Move(obj, 'y', y);
            PrepareScanInTwoDimensions(obj, x, z, nFlat, nOverRun, tPixel, 'x', 'z');
            QueryPos(obj);
        end
        
        function PrepareScanYX(obj, x, y, z, nFlat, nOverRun, tPixel)
            %%%%%%%%%%%%%% TWO DIMENSIONAL XY SCAN MACRO %%%%%%%%%%%%%%
            % Prepare a macro scan for xy axes!
            % Scanning is done by calling 'ScanNextLine'.
            % Aborting via 'AbortScan'.
            % x/y - Vectors with the points to scan, points should have
            % equal distance between them.
            % z - The starting points for the other axis.
            % nFlat - How many flat points should be in the beginning of the scan.
            % nOveRun - How many extra points should be taken from each.
            % tPixel - Scan time for each pixel.
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            if obj.scanRunning
                obj.sendWarning('2D Scan is in progress, previous scan canceled');
                AbortScan(obj);
            end
            Move(obj, 'z', z);
            PrepareScanInTwoDimensions(obj, y, x, nFlat, nOverRun, tPixel, 'y', 'x');
            QueryPos(obj);
        end
        
        function PrepareScanYZ(obj, x, y, z, nFlat, nOverRun, tPixel)
            %%%%%%%%%%%%%% TWO DIMENSIONAL YZ SCAN MACRO %%%%%%%%%%%%%%
            % Prepare a macro scan for yz axes!
            % Scanning is done by calling 'ScanNextLine'.
            % Aborting via 'AbortScan'.
            % y/z - Vectors with the points to scan, points should have
            % equal distance between them.
            % x - The starting points for the other axis.
            % nFlat - How many flat points should be in the beginning of the scan.
            % nOveRun - How many extra points should be taken from each.
            % tPixel - Scan time for each pixel.
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            if obj.scanRunning
                obj.sendWarning('2D Scan is in progress, previous scan canceled');
                AbortScan(obj);
            end
            Move(obj, 'x', x);
            PrepareScanInTwoDimensions(obj, y, z, nFlat, nOverRun, tPixel, 'y', 'z');
            QueryPos(obj);
        end
        
        function PrepareScanZX(obj, x, y, z, nFlat, nOverRun, tPixel)
            %%%%%%%%%%%%%% TWO DIMENSIONAL XZ SCAN MACRO %%%%%%%%%%%%%%
            % Prepare a macro scan for xz axes!
            % Scanning is done by calling 'ScanNextLine'.
            % Aborting via 'AbortScan'.
            % x/z - Vectors with the points to scan, points should have
            % equal distance between them.
            % y - The starting points for the other axis.
            % nFlat - How many flat points should be in the beginning of the scan.
            % nOveRun - How many extra points should be taken from each.
            % tPixel - Scan time for each pixel.
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            if obj.scanRunning
                obj.sendWarning('2D Scan is in progress, previous scan canceled');
                AbortScan(obj);
            end
            Move(obj, 'y', y);
            PrepareScanInTwoDimensions(obj, z, x, nFlat, nOverRun, tPixel, 'z', 'x');
            QueryPos(obj);
        end
        
        function PrepareScanZY(obj, x, y, z, nFlat, nOverRun, tPixel)
            %%%%%%%%%%%%%% TWO DIMENSIONAL YZ SCAN MACRO %%%%%%%%%%%%%%
            % Prepare a macro scan for yz axes!
            % Scanning is done by calling 'ScanNextLine'.
            % Aborting via 'AbortScan'.
            % y/z - Vectors with the points to scan, points should have
            % equal distance between them.
            % x - The starting points for the other axis.
            % nFlat - How many flat points should be in the beginning of the scan.
            % nOveRun - How many extra points should be taken from each.
            % tPixel - Scan time for each pixel.
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            if obj.scanRunning
                obj.sendWarning('2D Scan is in progress, previous scan canceled');
                AbortScan(obj);
            end
            Move(obj, 'x', x);
            PrepareScanInTwoDimensions(obj, z, y, nFlat, nOverRun, tPixel, 'z', 'y');
            QueryPos(obj);
        end
        
        function forwards = ScanNextLine(obj)
            % Scans the next line for the 2D scan, to be used after
            % 'PrepareScanXX'.
            % No other commands should be used between 'PrepareScanXX' or
            % until 'AbortScan' has been called.
            % forwards is set to 1 when the scan is forward and is set to 0
            % when it's backwards
            obj.sendWarning(sprintf('Scan not implemented for the %s controller.\n', obj.controllerModel));
            forwards = 1;
        end
        
        function PrepareRescanLine(obj)
            % Prepares the previous line for rescanning.
            % Scanning is done with "ScanNextLine"
            obj.sendWarning(sprintf('Scan not implemented for the %s controller.\n', obj.controllerModel));
        end
        
        function AbortScan(obj) %#ok<MANU>
            % Aborts the 2D scan defined by 'PrepareScanXX';
        end
        
        function maxScanSize = ReturnMaxScanSize(obj, nDimensions) %#ok<INUSD>
            % Returns the maximum number of points allowed for an
            % 'nDimensions' scan.
            maxScanSize = obj.maxScanSize;
        end
        
         function [tiltEnabled, thetaXZ, thetaYZ] = GetTiltStatus(obj)
            % Return the status of the tilt control.
            tiltEnabled = obj.tiltCorrectionEnable;
            thetaXZ = obj.tiltThetaXZ;
            thetaYZ = obj.tiltThetaYZ;
          end 
        
        function JoystickControl(obj, enable) %#ok<INUSD>
            % Changes the joystick state for all axes to the value of
            % 'enable' - 1 to turn Joystick on, 0 to turn it off.
            obj.sendWarning(sprintf('No joystick support for the %s controller.\n', obj.controllerModel));
        end
        
        function binaryButtonState = ReturnJoystickButtonState(obj)
            % Returns the state of the buttons in 3 bit decimal format.
            % 1 for first button, 2 for second and 4 for the 3rd.
            obj.sendWarning(sprintf('No joystick support for the %s controller.\n', obj.controllerModel));
            binaryButtonState = 0;
        end
        
        function FastScan(obj, enable) %#ok<INUSD>
            % Changes the scan between fast & slow mode
            % 'enable' - 1 for fast scan, 0 for slow scan.
            obj.sendWarning(sprintf('Scan not implemented for the %s controller.\n', obj.controllerModel));
        end
        
        function ReadLoopMode(obj)
            % This stage has both loop modes FOR EACH of the of the axes,
            % but we always set them all at once, so it is enough to check
            % the mode for one of the axes (0 == x axis).
            
            SA_CTL_PKEY_CONTROL_LOOP_INPUT; % todo: set value according to .h file
            
            [lMode, ~]  = SendCommand(obj, 'SA_CTL_SetProperty_i32', obj.id, ...
                0, SA_CTL_PKEY_CONTROL_LOOP_INPUT, [], []);
            % ^ This returns either 0, if open loop, or 1 otherwise.
            obj.loopMode = BooleanHelper.ifTrueElse(lMode, 'Closed', 'Open');
        end
        
        function ChangeLoopMode(obj, mode)
            % Changes between closed and open loop.
            % 'mode' should be either 'Open' or 'Closed'.
            % Stage will auto-lock when in open mode, which should increase
            % stability.
            SA_CTL_PKEY_CONTROL_LOOP_INPUT % todo
            
            switch mode
                case 'Open'
                    modeInternal = 0; % Closed loop disabled
                case 'Closed'
                    modeInternal = 1; % Closed loop enabled (internal sensor)
                otherwise
                    obj.sendError(sprintf('Unknown mode %s', mode));
            end
            for channel = 0:2
                SendCommand(obj, 'SA_CTL_SetProperty_i32', obj.id, channel, SA_CTL_PKEY_CONTROL_LOOP_INPUT, modeInternal);
            end
            
            obj.loopMode = mode;
            obj.sendEventStageAvailabilityChanged;
        end
        
        function success = EnableTiltCorrection(obj, enable)
            % Enables the tilt correction according to the angles.
            if ~strcmp(obj.VALID_AXES, obj.axesName)
                string = BooleanHelper.ifTrueElse(isscalar(obj.VALID_AXES), 'axis', 'axes');
                obj.sendWarning(sprintf('Controller %s has only %s %s, and can''t do tilt correction.', ...
                    obj.controllerModel, obj.VALID_AXES, string));
                success = 0;
                return;
            end
            obj.tiltCorrectionEnable = enable;
            success = 1;
        end
        
        function success = SetTiltAngle(obj, thetaXZ, thetaYZ)
            % Sets the tilt angles between Z axis and XY axes.
            % Angles should be in degrees, valid angles are between -5 and 5
            % degrees.
            if (thetaXZ < -5 || thetaXZ > 5) || (thetaYZ < -5 || thetaYZ > 5)
                obj.sendWarning(sprintf('Angles are outside the limits (-5 to 5 degrees).\nAngles were not set.'));
                success = 0;
                return
            end
            obj.tiltThetaXZ = thetaXZ;
            obj.tiltThetaYZ = thetaYZ;
            success = 1;
        end
    end
end