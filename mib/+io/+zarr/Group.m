classdef Group < handle
% GROUP - backend-agnostic handle to an OME-Zarr v3 group.
%
% Drop-in replacement for ``ZarrGroup``. Group/array **metadata** and
% **attributes** are always handled natively (``ZarrGroup`` over ``zarrMex``)
% so the on-disk structure is identical for every backend; arrays returned by
% ``createArray`` / ``openArray`` are ``io.zarr.Array`` handles whose bulk I/O
% follows ``io.zarr.Config``.
%
% **Examples**
%
%   .. code-block:: matlab
%
%      grp = io.zarr.Group.create('C:\data\out.zarr3');
%      arr = grp.createArray('0', [512 512 20], 'uint16', 'chunkShape', [512 512 4]);
%      arr.write(uint16(zeros(512, 512, 20)));        % uses active backend
%      grp.setAttributes(struct('multiscales', {{ ... }}));
%
%      grp = io.zarr.Group('C:\data\out.zarr3');      % reopen
%      a0  = grp.openArray('0');
%      ms  = grp.getAttributes();

    properties (SetAccess = private)
        path
        % [char] group path (local folder or HTTP/HTTPS URL).
    end

    properties (Access = private)
        nativeGrp        % cached ZarrGroup handle (metadata/attributes)
    end

    methods
        function obj = Group(path)
            % GROUP - open an existing zarr group (validates it is a group).
            obj.path = char(path);
            obj.nativeGrp = ZarrGroup(obj.path);
        end

        function arr = createArray(obj, name, shape, dataType, varargin)
            % CREATEARRAY - create an array in this group (native metadata),
            % returning an io.zarr.Array bound to the active backend.
            obj.nativeGrp.createArray(name, shape, dataType, varargin{:});
            arr = io.zarr.Array(io.zarr.Group.childPath(obj.path, name));
        end

        function arr = openArray(obj, name)
            % OPENARRAY - open an existing array in this group.
            arr = io.zarr.Array(io.zarr.Group.childPath(obj.path, name));
        end

        function attrs = getAttributes(obj)
            % GETATTRIBUTES - return the group's attributes struct.
            attrs = obj.nativeGrp.getAttributes();
        end

        function setAttributes(obj, attrs)
            % SETATTRIBUTES - overwrite the group's attributes.
            obj.nativeGrp.setAttributes(attrs);
        end
    end

    methods (Static)
        function obj = create(path)
            % CREATE - create a new zarr group (native metadata) and wrap it.
            ZarrGroup.create(char(path));
            obj = io.zarr.Group(char(path));
        end
    end

    methods (Static, Access = private)
        function p = childPath(base, name)
            % CHILDPATH - join a child node name to a group path (fs or HTTP).
            base = char(base); name = char(name);
            if startsWith(base, 'http://') || startsWith(base, 'https://')
                if endsWith(base, '/'); p = [base, name]; else; p = [base, '/', name]; end
            else
                p = fullfile(base, name);
            end
        end
    end
end
