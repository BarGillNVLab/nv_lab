classdef SaveLoadImageLocal < SaveLoadCatImage
    %SAVELOADIMAGELOCAL SaveLoad for dev purposes
    
    properties
    end
    
    methods
        function obj = SaveLoadImageLocal
            obj@SaveLoadCatImage;
            root = 'C:\\SourceCode\\Dev';
            obj.mSavingFolder = [root '\\_ManualSaves\\Setup 999\\'];  % to be overridden later by the user, if needed...
            obj.mLoadingFolder = [root '\\_AutoSave\\Setup 999\\'];    % to be overridden later by the user, if needed...
        end
        
        % Overloading
        function autoSave(obj)
            % Saves the experiment results the local struct into a file
            % in the AUTOSAVE folder
            
            filename = obj.mLoadedFileName;
            fullPath = sprintf('%s%s', obj.mLoadingFolder, filename);
            
            newStructStatus = obj.STRUCT_STATUS_AUTO_SAVED;
            obj.saveLocalStructToFile(fullPath, newStructStatus);
        end
    end
end

