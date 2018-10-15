classdef GuiControllerLoadImage < GuiController
       
    
    properties
        folder
        fileName
    end
       
    methods
        function obj = GuiControllerLoadImage(imgFolder)
            Setup.init;
            shouldConfirmOnExit = false;
            windowName = 'Gui Load Image';
            openOnlyOne = true;  
           
            
            obj = obj@GuiController(windowName, shouldConfirmOnExit, openOnlyOne);
            obj.folder=imgFolder;
            ob=viewImg(windowName,controller,obj.folder);
            obj.fileName=ob.files;
        end
        
        function view = getMainView(obj, figureWindowParent)
            % this function should get the main View of this GUI.
            % can call any view constructor with the params:
            %
            ViewImg.init(figureWindowParent, obj);
            view = getObjByName( figureWindowParent, objViewImg.NAME);
        end
        
        function onAboutToStart(obj)
            % callback. things to run right before the window will be drawn
            % to the screen.
            % child classes can override this method
            obj.moveToMiddleOfScreen();
        end
        
        function onSizeChanged(obj, newX0, newY0, newWidth, newHeight)
            % callback. thigs to run when the window size is changed
            % child classes can override this method
            fprintf('width: %d, height: %d\n', newWidth, newHeight);
        end

    end
    
end