classdef ViewImageResultImage < GuiComponent
    %VIEWIMAGERESULTIMAGE view that shows the scan results
    %   it is being used by other GUI components (such as the various
    %   options above it) as well as the StageScanner when it needs to
    %   duplicate the axes() object (which is obj.vAxes)
    
    properties
        vAxes       % the axes view to use for the plotting
    end
    properties (Constant)
        NAME = 'ViewImageResultImage';
    end
    
    methods
        function obj = ViewImageResultImage(parent, controller)
            obj@GuiComponent(parent, controller);
            imageScanResult = getObjByName(ImageScanResult.NAME);
            
            obj.component = uicontainer('parent', parent.component);
            obj.vAxes = axes('Parent', obj.component, 'ActivePositionProperty', 'outerposition');
            imageScanResult.addGraphicAxes(obj.vAxes);
            
            % Set colormap and colorbar
            cMap = imageScanResult.COLORMAP_OPTIONS{imageScanResult.colormapType};
            colormap(obj.vAxes, cMap);
            
            % Creating floating axes() so that default calls to axes (such
            % as image() surf() etc.) won't reach this view but rather the
            % invisible floating one
            axes();
            imageScanResult.update;
            
            obj.height = 600;   % minimum
            obj.width = 600;    % minimum
        end
    end
end