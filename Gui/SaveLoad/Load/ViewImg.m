classdef ViewImg < ViewVBox & EventListener
    
    properties
        files
        vImage  % the image view
        pnjFile
        matFile
    end
    properties (Constant)
        NAME = 'ImgLoad';
    end
    methods
        function obj = ViewImg(parent, controller,folder)
            horizSize = 2;
            verticSize = 2;
            totalSize = horizSize * verticSize;
            
            Im = NaN(horizSize, verticSize);
            
            obj@ViewVBox(parent, controller);
            %obj.vImage= ViewImageResultImage(obj, controller);
            obj.files = PathHelper.getAllFilesInFolder(folder ,'png');
            %len=length(obj.files);
            for i=1 : totalSize
                subplot(horizSize,verticSize,i);
                imshow(obj.files{i});
                Im(i).ButtonDownFcn = @(h,e) obj.imageButtonDownCallback(i);
            end
            
            uiwait

            
        end
        
        function imageButtonDownCallback(obj, i)
           obj.pnjFile=obj.files{i};
           obj.matFile=PathHelper.removeDotSuffix(obj.pnjFile);
           obj.matFile=[obj.matFile '.mat'];
           
            
        end
    end
end