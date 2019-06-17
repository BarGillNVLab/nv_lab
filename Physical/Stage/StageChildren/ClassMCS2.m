classdef ClassMCS2 < ClassStage
    % 
    % libfunctionsview('MCS2') to view functions
    
    properties (Constant)
        NAME = 'Stage (Fine) - MCS2'
        VALID_AXES = 'xyz';
        UNITS = 'um'
        
        NEEDED_FIELDS = {'niDaqChannel', 'address'}
        
        COMM_DELAY = 0.005; % 5ms delay needed between consecutive commands sent to the controllers.
        
        LIB_DLL_FOLDER = 'C:/Users/Owner/Google Drive/NV Lab/Control code/Drivers/SmarAct/MCS2/SDK/lib64/';
        LIB_DLL_FILENAME = 'SmarActCTL.dll';
        LIB_ALIAS = 'MCS2';

        POSITIVE_HARD_LIMITS = [8000 8000 16000];   % in um
        NEGATIVE_HARD_LIMITS = [-8000 -8000 0];     % in um
        LOGICAL_SCALE_OFFSET = [0 0 -8e9];          % in pm
        STEP_MINIMUM_SIZE = 0.001                   % in um
        STEP_DEFAULT_SIZE = 0.02                    % in um
    end
       
    properties (Access = protected)
        physicalAddress
        id
        posSoftRangeLimit
        negSoftRangeLimit
        defaultVel = 1e3;   % in um/s (== 1mm/s)
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
    
    methods (Static)
        function obj = create(stageStruct)
            % Get instance constructor
            missingField = FactoryHelper.usualChecks(stageStruct, ClassMCS2.NEEDED_FIELDS);
            if ~isnan(missingField)
                EventStation.anonymousError(...
                    'Trying to create the MCS2 stage, needed field "%s" was missing. Aborting',...
                    missingField);
            end
            
            niDaqChannel = stageStruct.niDaqChannel;
            address = stageStruct.address;
            removeObjIfExists(ClassMCS2.NAME);
            obj = ClassMCS2(address, niDaqChannel);
        end
    end
    
    methods (Access = protected) % Protected Functions
        function obj = ClassMCS2(address, niDaqChannel)
            % name - string
            % availableAxes - string. example: "xyz"
            name = ClassMCS2.NAME;
            availableAxes = ClassMCS2.VALID_AXES;
            obj@ClassStage(name, availableAxes)
            
            obj.tiltCorrectionEnable = 0;
            obj.tiltThetaXZ = 0;
            obj.tiltThetaYZ = 0;
            obj.negSoftRangeLimit = obj.NEGATIVE_HARD_LIMITS;
            obj.posSoftRangeLimit = obj.POSITIVE_HARD_LIMITS;
            
            obj.physicalAddress = address;
            obj.LoadPiezoLibrary();
            obj.Connect;
            
            nidaq = getObjByName(NiDaq.NAME);
            nidaq.registerChannel(niDaqChannel, obj.name);
            
            Initialization(obj);
        end

        function Connect(obj)
            locator = obj.physicalAddress;
            [obj.id, ~, ~] = obj.SendCommand('SA_CTL_Open', 0, locator, '');
        end
        
        function Delay(obj, seconds) %#ok<INUSL>
            % Pauses for the given seconds.
            delay = tic;
            while toc(delay) < seconds
            end
        end
        
        function CommunicationDelay(obj)
            % Pauses for obj.commDelay seconds.
            obj.Delay(obj.COMM_DELAY);
        end
        
        function varargout = SendCommand(obj, command, realAxis, varargin)
            % Send the command to the controller and returns the output.
            % Automatically adds a waiting period before the command is
            % sent.
            % The first returned output from the command is not returned
            % and is treated as a return code. (Checked for errors)
            
            % Try sending command
            returnCode = -1;
            tries = 0;
            while ~(returnCode == 0)
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
                                    % We stay in the loop
                                case abortString
                                    obj.sendError(error.message);
                                    % We exit the loop
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
            
            if ~(returnCode == 0)   % All error codes appear in Appendix A of the Programmer's Guide
                errorMessage = SendCommandWithoutReturnCode(obj, 'SA_CTL_GetResultInfo', returnCode);
                errorCode = lower(dec2hex(returnCode, 4));
                errorId = sprintf('MCS2:x%s', errorCode);
                error(errorId, 'The following error was received while attempting to communicate with MCS2 controller:\n%s Error  - %s',...
                    ['0x' errorCode], errorMessage);
            end
        end
        
        function LoadPiezoLibrary(obj)
            % Loads the MCS2 dll file.

            if ~libisloaded(obj.LIB_ALIAS)
                % Only load dll if it wasn't loaded before.
                shrlib = [obj.LIB_DLL_FOLDER, obj.LIB_DLL_FILENAME];
                
                loadlibrary(shrlib, @mcs2proto, 'alias', obj.LIB_ALIAS);
                fprintf('MCS2 library loaded.\n');
            end
        end
        
        function DisconnectController(obj)
            % This function disconnects the controller at the given ID
            SendCommand(obj, 'SA_CTL_Cancel', obj.id);
            SendCommand(obj, 'SA_CTL_Close', obj.id); 
        end
        
        function chState = getChannelState(obj, channelIndex)
            SA_CTL_PKEY_CHANNEL_STATE = 50659343;   % 0x0305000F
            
            chState = SendCommand(obj, 'SA_CTL_GetProperty_i32', obj.id, ...
                channelIndex, SA_CTL_PKEY_CHANNEL_STATE, 0, 1);
        end
        
        function axisIndex = GetAxisIndex(obj, phAxis)
            % Converts x,y,z into the corresponding index for this
            % controller; if stage only has 'z' then z is 1.
            phAxis = GetAxis(obj, phAxis);
            CheckAxis(obj, phAxis)
            axisIndex = zeros(size(phAxis));
            for i = 1:length(phAxis)
                idx = phAxis(i);
                if idx > length(obj.availableAxes)
                    obj.sendError('Invalid axis')
                end
                axisIndex(i) = idx - 1;     % MATLAB starts counting from 1, but the stage counts from 0
            end
        end
        
        function CheckAxis(obj, phAxis)
            % Checks that the given axis matches the connected stage.
            % 'phAxis' can be either a specific axis (x,y,z or 1 for x,
            % 2 for y, and 3 for z) or any vectorial combination of them.
            phAxis = obj.GetAxis(phAxis);
            if ~isempty(setdiff(phAxis, GetAxis(obj, obj.VALID_AXES)))
                if isscalar(phAxis)
                    string = 'axis is';
                else
                    string = 'axes are';
                end
                obj.sendError(sprintf('%s %s invalid for the MCS2 controller.', upper(obj.SCAN_AXES(phAxis)), string));
            end
        end
        
        function CheckReference(obj, phAxis)
            % Checks whether the given (physical) axis is referenced, 
            % and if not, asks for confirmation to reference it.
            phAxis = GetAxis(obj, phAxis);
            referenced = IsRefernced(obj, phAxis);
            if all(referenced)
                % We are done
                return
            end
            
            % Otherwise
            unreferncedAxesNames = obj.VALID_AXES(phAxis(~referenced));
            if isscalar(unreferncedAxesNames)
                questionStringPart1 = sprintf('WARNING!\n%s axis is unreferenced.\n', unreferncedAxesNames);
            else
                questionStringPart1 = sprintf('WARNING!\n%s axes are unreferenced.\n', unreferncedAxesNames);
            end
            % Ask for user confirmation
            questionStringPart2 = sprintf('Stages must be referenced before use.\nThis will move the stages.\nPlease make sure the movement will not cause damage to the equipment!');
            questionString = [questionStringPart1 questionStringPart2];
            titleString = 'Referencing Confirmation';
            referenceString = 'Reference';
            referenceCancelString = 'Cancel';
            confirm = questdlg(questionString, titleString, referenceString, referenceCancelString, referenceCancelString);
            switch confirm
                case referenceString
                    Refernce(obj, phAxis)
                case referenceCancelString
                    obj.sendError(sprintf('Referencing cancelled for controller MCS2: %s', ...
                        unreferncedAxesNames));
                otherwise
                    obj.sendError(sprintf('Referencing failed for controller MCS2: %s - No user confirmation was given', ...
                        unreferncedAxesNames));
            end
        end
        
        function tf = IsRefernced(obj, phAxis)
            % Check reference status for the given axis.
            % 'phAxis' can be either a specific axis (x,y,z or 1 for x, 2 for y
            % and 3 for z) or any vectorial combination of them.
            len = length(phAxis);
            tf = false(1, len);
            realAxis = obj.GetAxisIndex(phAxis);
            
            for i = 1:length(realAxis)
                chState = obj.getChannelState(realAxis(i));
                tf(i) = bitget(chState, 8);     % Bit 7, if we count from 0
            end
            tf = logical(tf);
        end
        
        function Refernce(obj, phAxis)
            % Reference the given axis.
            % 'phAxis' can be either a specific axis (x,y,z or 1 for x, 2 for y
            % and 3 for z) or any vectorial combination of them.
            CheckAxis(obj, phAxis)
            realAxis = GetAxisIndex(obj, phAxis);
            
            len = length(realAxis);
            isRef = zeros(1, len);
            for i = 1:len
                p = phAxis(i);
                SendCommand(obj, 'SA_CTL_Reference', obj.id, realAxis(i), 0);
                WaitFor(obj, 'ReferencingDone', p)
                isRef(i) = IsRefernced(obj, p);
            end
            
            % Check if ready & if referenced succeeded
            if (~all(isRef))
                obj.sendError(sprintf('Referencing failed for controller MCS2 with ID %d: Reason unknown.', ...
                    obj.id));
            end
        end
        
        function tf = IsCalibrated(obj, phAxis)
            % Check reference status for the given axis.
            % 'phAxis' can be either a specific axis (x,y,z or 1 for x, 2 for y
            % and 3 for z) or any vectorial combination of them.
            len = length(phAxis);
            tf = false(1, len);
            realAxis = obj.GetAxisIndex(phAxis);
            
            for i = 1:length(realAxis)
                chState = obj.getChannelState(realAxis(i));
                tf(i) = bitget(chState, 7);     % Bit 6, if we count from 0
            end
            tf = logical(tf);
        end
        
        function Calibrate(obj, phAxis)
            % Reference the given axis.
            % 'phAxis' can be either a specific axis (x,y,z or 1 for x, 2 for y
            % and 3 for z) or any vectorial combination of them.
            CheckAxis(obj, phAxis)
            realAxis = GetAxisIndex(obj, phAxis);
            
            len = length(realAxis);
            isCalib = zeros(1, len);
            for i = 1:len
                p = phAxis(i);
                SendCommand(obj, 'SA_CTL_Calibrate', obj.id, realAxis(i), 0);
                WaitFor(obj, 'CalibratingDone', p)
                isCalib(i) = IsCalibrated(obj, p);
            end
            
            % Check if ready & if referenced succeeded
            if (~all(isCalib))
                obj.sendError(sprintf('Calibration failed for controller MCS2 with ID %d: Reason unknown.', ...
                    obj.id));
            end
        end
        
        function Initialization(obj)
            % Initializes the piezo stages.
            obj.scanRunning = 0;

            % Change to closed loop
            ChangeLoopMode(obj, 'Closed')
            
            % Checks
%             CheckCalibration(obj, obj.VALID_AXES)
            CheckReference(obj, obj.VALID_AXES)
            CheckModuleParameters(obj);
            
            % Set velocity
            SetVelocity(obj, obj.VALID_AXES, zeros(size(obj.VALID_AXES))+obj.defaultVel);
            
            % Update position and velocity
            QueryPos(obj);
            QueryVel(obj);
            for i=1:length(obj.VALID_AXES)
                fprintf('%s axis - Position: %.4f%s, Velocity: %d%s/s.\n', upper(obj.VALID_AXES(i)), obj.curPos(i), obj.UNITS, obj.curVel(i), obj.UNITS);
            end
        end
        
        function CheckModuleParameters(obj)
            % This function checks that the logical scale and the safe
            % direction are defined according to our use.
            
            for i=1:length(obj.VALID_AXES)
                realAxis = obj.GetAxisIndex(obj.VALID_AXES(i));
                
                % Logical Scale Offset
                SA_CTL_PKEY_LOGICAL_SCALE_OFFSET = 33816612; % 0x02040024
                offset = SendCommand(obj, 'SA_CTL_GetProperty_i64', obj.id, ...
                    realAxis, SA_CTL_PKEY_LOGICAL_SCALE_OFFSET, 0, 1);
                if offset ~= obj.LOGICAL_SCALE_OFFSET(i)
                    SendCommand(obj, 'SA_CTL_SetProperty_i64', obj.id, realAxis, ...
                        SA_CTL_PKEY_LOGICAL_SCALE_OFFSET, obj.LOGICAL_SCALE_OFFSET(i));
                    obj.sendWarning(sprintf(['Scale offset in axis %s needed resetting. ', ...
                        'If this a recurring problem, the code might need maintenance'], ...
                        obj.VALID_AXES(i)));
                end
                
                % Logical Scale Inversion
                SA_CTL_PKEY_LOGICAL_SCALE_INVERSION = 33816613; % 0x02040025
                SA_CTL_INVERTED = 1;
                isInverted = SendCommand(obj, 'SA_CTL_GetProperty_i32', obj.id, realAxis, SA_CTL_PKEY_LOGICAL_SCALE_INVERSION, 0, 1);
                if isInverted ~= SA_CTL_INVERTED
                    SendCommand(obj, 'SA_CTL_SetProperty_i32', obj.id, realAxis, ...
                        SA_CTL_PKEY_LOGICAL_SCALE_INVERSION, SA_CTL_INVERTED);
                    obj.sendWarning(sprintf(['Scale inversion in axis %s needed resetting. ', ...
                        'If this a recurring problem, the code might need maintenance'], ...
                        obj.VALID_AXES(i)));
                end
                
                % Safe Direction
                SA_CTL_PKEY_SAFE_DIRECTION = 50921511; % 0x03090027
                SA_CTL_FORWARD_DIRECTION = 0;
                safeDir = SendCommand(obj, 'SA_CTL_GetProperty_i32', obj.id, realAxis, SA_CTL_PKEY_SAFE_DIRECTION, 0, 1);
                if safeDir ~= SA_CTL_FORWARD_DIRECTION
                    SendCommand(obj, 'SA_CTL_SetProperty_i32', obj.id, realAxis, ...
                        SA_CTL_PKEY_SAFE_DIRECTION, SA_CTL_FORWARD_DIRECTION);
                    
                    axisLetter = obj.VALID_AXES(i);
                    phAxis = obj.getAxis(axisLetter);
                    strTitle = sprintf('Calibration needed for MCS2 controller');
                    strQstnMsg = sprintf('Axis %s requires calibration, which will move it.\nFailing to do so might result in unexpected behavior.', axisLetter);
                    isOK = QuestionUserOkCancel(strTitle, strQstnMsg);
                    if isOK
                        Calibrate(obj, phAxis);
                    end
                    
                end
            end
        end
        
        function QueryPos(obj)
            % Queries the position and updates the internal variable.
            SA_CTL_PKEY_POSITION = 50659357; % 0x0305001D
            for i = 1:length(obj.VALID_AXES)
                realAxis = GetAxisIndex(obj, obj.VALID_AXES(i));
                pos = SendCommand(obj, 'SA_CTL_GetProperty_i64', obj.id, realAxis, SA_CTL_PKEY_POSITION, 0, 1);
                obj.curPos(i) = double(pos) * 1e-6; % Convert from pm to um
            end
        end
        
        function QueryVel(obj)
            % Queries the velocity and updates the internal variable.
            SA_CTL_PKEY_MOVE_VELOCITY = 50659369; % 0x03050029
            for i = 1:length(obj.VALID_AXES)
                realAxis = GetAxisIndex(obj, obj.VALID_AXES(i));
                vel = SendCommand(obj, 'SA_CTL_GetProperty_i64', obj.id, realAxis, SA_CTL_PKEY_MOVE_VELOCITY, 0, 1);
                obj.curVel(i) = double(vel) * 1e-6; % Convert from pm to um
            end
        end
        
        function WaitFor(obj, what, phAxis)
            % Waits until a specific action, defined by what, is finished.
            % 'phAxis' must a specific (physical) axis (x,y,z or 
            % 1 for x, 2 for y and 3 for z).
            % Current options for 'what':
            % MovementDone - Waits until movement is done.
            % ReferencingDone - waits until referencing is done.
%             % onTarget - Waits until the stage reaches it's target.
%             % ControllerReady - Waits until the controller is ready (Not
%             % need for axis)
            % WaveGeneratorDone - Waits unti the wave generator is done.
            CheckAxis(obj, phAxis);
            realAxis = GetAxisIndex(obj, phAxis);
                
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
                        chState = getChannelState(obj, realAxis);
                        isMoving = bitget(chState, 1);	% Bit 0 (1st bit) is SA_CTL_CH_STATE_BIT_ACTIVELY_MOVING
                        wait = isMoving;
                    case 'CalibratingDone'
                        chState = getChannelState(obj, realAxis);
                        isCalibrating = bitget(chState, 3);	% Bit 2 (from 0) is SA_CTL_CH_STATE_BIT_CALIBRATING
                        wait = isCalibrating;
                    case 'ReferencingDone'
                        chState = getChannelState(obj, realAxis);
                        isReferencing = bitget(chState, 4);	% Bit 3 (from 0) is SA_CTL_CH_STATE_BIT_REFERENCING
                        wait = isReferencing;
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
            
            CheckReference(obj, phAxis)
            
            % Convert position to pm, which are the units the stage
            % recieves
            pos = pos * 1e6;
            
            % Send the move command
            SA_CTL_PKEY_MOVE_MODE = 50659463;   % 0x03050087
            SA_CTL_MOVE_MODE_CL_ABSOLUTE = 0;
            realAxes = GetAxisIndex(obj, phAxis);
            for i = 1:length(realAxes)
                obj.SendCommand('SA_CTL_SetProperty_i32', obj.id, realAxes(i), ...
                    SA_CTL_PKEY_MOVE_MODE, SA_CTL_MOVE_MODE_CL_ABSOLUTE);
                obj.SendCommand('SA_CTL_Move', obj.id, realAxes(i), pos(i), 0)
            end
            
            % Wait for move command to finish
            WaitFor(obj, 'MovementDone', phAxis)
        end

        function HaltPrivate(obj, phAxis)
            % Halts the stage.
            SA_CTL_PKEY_MOVE_MODE = 50659463;   % 0x03050087
            SA_CTL_MOVE_MODE_CL_RELATIVE = 1;
            
            realAxes = GetAxisIndex(obj, phAxis);
            for i = 1:length(realAxes)
                obj.SendCommand('SA_CTL_SetProperty_i32', obj.id, realAxes(i), ...
                    SA_CTL_PKEY_MOVE_MODE, SA_CTL_MOVE_MODE_CL_RELATIVE);
                obj.SendCommand('SA_CTL_Move', obj.id, realAxes(i), 0, 0)
            end
            AbortScan(obj)
            obj.sendWarning('Stage Halted!');
        end
        
        function SetVelocityPrivate(obj, phAxis, vel)
            % Absolute change in velocity (vel) of axis (x,y,z or 1 for x,
            % 2 for y and 3 for z).
            % Does not check if scan is running.
            % Vectorial axis is possible.
            SA_CTL_PKEY_MOVE_VELOCITY = 50659369;   % 0x03050029
            
            CheckAxis(obj, phAxis)
            vel = vel * 1e6; % Convert from um/s to pm/s
            for i = 1:length(phAxis)
                realAxis = GetAxisIndex(obj, phAxis(i));
                obj.SendCommand('SA_CTL_SetProperty_i64', obj.id, realAxis, ...
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
            if ~contains(obj.SCAN_AXES(phAxis), 'z') % Only do something if there is no z axis
                QueryPos(obj);
                pos = [pos, obj.curPos(3)]; % Adds the z position command, start by writing the current position (as the base)
                for i=1:length(phAxis)
                    switch obj.SCAN_AXES(phAxis)
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
            if (obj.id ~= -1)
                % ID exists, attempt to close
                DisconnectController(obj)
                fprintf('Connection to controller MCS2 closed: ID %d released.\n', obj.id);
            else
                % obj.ForceCloseConnection(obj.controllerModel);
                obj.sendWarning('Could not close connection to MCS2 controller!')
            end
            obj.id = -1;
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
            axisIndex = GetAxis(obj, phAxis);
            ok = all((point >= obj.negSoftRangeLimit(axisIndex)) & (point <= obj.posSoftRangeLimit(axisIndex)));
        end
        
        function [negSoftLimit, posSoftLimit] = ReturnLimits(obj, phAxis)
            % Return the soft limits of the given axis (x,y,z or 1 for x,
            % 2 for y and 3 for z).
            % Vectorial axis is possible.
            CheckAxis(obj, phAxis)
            axisIndex = GetAxis(obj, phAxis);
            negSoftLimit = obj.negSoftRangeLimit(axisIndex);
            posSoftLimit = obj.posSoftRangeLimit(axisIndex);
        end
        
        function [negHardLimit, posHardLimit] = ReturnHardLimits(obj, phAxis)
            % Return the hard limits of the given axis (x,y,z or 1 for x,
            % 2 for y and 3 for z).
            % Vectorial axis is possible.
            CheckAxis(obj, phAxis)
            axisIndex = GetAxis(obj, phAxis);
            negHardLimit = obj.NEGATIVE_HARD_LIMITS(axisIndex);
            posHardLimit = obj.POSITIVE_HARD_LIMITS(axisIndex);
        end
        
        function SetSoftLimits(obj, phAxis, softLimit, negOrPos)
            % Set the new soft limits:
            % if negOrPos = 0 -> then softLimit = lower soft limit
            % if negOrPos = 1 -> then softLimit = higher soft limit
            % This is because each time this function is called only one of
            % the limits updates
            CheckAxis(obj, phAxis)
            axisIndex = GetAxis(obj, phAxis);
            if ((softLimit >= obj.NEGATIVE_HARD_LIMITS(axisIndex)) && (softLimit <= obj.POSITIVE_HARD_LIMITS(axisIndex)))
                if negOrPos == 0
                    obj.negSoftRangeLimit(axisIndex) = softLimit;
                else
                    obj.posSoftRangeLimit(axisIndex) = softLimit;
                end
            else
                obj.sendError(sprintf('Soft limit %.4f is outside of the hard limits %.4f - %.4f', ...
                    softLimit, obj.NEGATIVE_HARD_LIMITS(axisIndex), obj.POSITIVE_HARD_LIMITS(axisIndex)))
            end
        end
        
        function pos = Pos(obj, phAxis)
            % Query and return position of axis (x,y,z or 1 for x, 2 for y
            % and 3 for z)
            % Vectorial axis is possible.
            CheckAxis(obj, phAxis)
            QueryPos(obj);
            axisIndex = GetAxis(obj, phAxis);
            pos = obj.curPos(axisIndex);
        end
        
        function vel = Vel(obj, phAxis)
            % Query and return velocity of axis (x,y,z or 1 for x, 2 for y
            % and 3 for z)
            % Vectorial axis is possible.
            CheckAxis(obj, phAxis)
            QueryVel(obj);
            axisIndex = GetAxis(obj, phAxis);
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
            axisIndex = GetAxis(obj, phAxis);
            Move(obj, phAxis, obj.curPos(axisIndex) + change); % Stage has its own "relative movement" option, but we do not use it.
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
            
            SA_CTL_PKEY_CONTROL_LOOP_INPUT = 50462744;  % 0x03020018
            
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
            SA_CTL_PKEY_CONTROL_LOOP_INPUT = 50462744;  % 0x03020018
            
            switch mode
                case 'Open'
                    modeInternal = 0; % Closed loop disabled
                case 'Closed'
                    modeInternal = 1; % Closed loop enabled (internal sensor)
                otherwise
                    obj.sendError(sprintf('Unknown mode %s', mode));
            end
            for channel = 0:2
                SendCommand(obj, 'SA_CTL_SetProperty_i32', obj.id, channel, ...
                    SA_CTL_PKEY_CONTROL_LOOP_INPUT, modeInternal);
            end
            
            obj.loopMode = mode;
            obj.sendEventStageAvailabilityChanged;
        end
        
        function success = EnableTiltCorrection(obj, enable)
            % Enables the tilt correction according to the angles.
            if ~strcmp(obj.VALID_AXES, obj.SCAN_AXES)
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