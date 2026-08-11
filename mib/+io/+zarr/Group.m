classdef Group < handle
% GROUP - backend-agnostic handle to an OME-Zarr v2 or v3 group.
%
% Drop-in replacement for ``ZarrGroup``. Group/array **metadata** and
% **attributes** are always handled natively (``ZarrGroup`` over ``zarrMex``)
% so the on-disk structure is identical for every backend; arrays returned by
% ``createArray`` / ``openArray`` are ``io.zarr.Array`` handles whose bulk I/O
% follows ``io.zarr.Config``.
%
% **Format is detected on open and inherited on create.** An existing group is
% opened whether it carries ``zarr.json`` (v3) or ``.zgroup`` (v2), and
% ``getAttributes`` / ``setAttributes`` read and write whichever of
% ``zarr.json`` / ``.zattrs`` that format uses. ``create`` defaults to v3;
% arrays added to a v2 group are created as v2 unless overridden, so the
% format only has to be named once, at the root.
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
%
%      % a zarr v2 pyramid: the levels inherit the group's format
%      grp = io.zarr.Group.create('C:\data\out.zarr2', 'zarrFormat', 2);
%      arr = grp.createArray('0', [512 512 20], 'uint8', 'chunkShape', [256 256 16]);

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
            %   The array inherits this group's zarr format unless the caller
            %   passes an explicit ``'zarrFormat'``.
            obj.nativeGrp.createArray(name, shape, dataType, varargin{:});
            arr = io.zarr.Array(io.zarr.Group.childPath(obj.path, name));
        end

        function format = zarrFormat(obj)
            % ZARRFORMAT - zarr format version of the group on disk (2 or 3).
            format = obj.nativeGrp.zarrFormat();
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
        function obj = create(path, varargin)
            % CREATE - create a new zarr group (native metadata) and wrap it.
            %   Accepts ZarrGroup.create's options, notably ``'zarrFormat'``
            %   (2 or 3, default 3), which every array added later inherits.
            ZarrGroup.create(char(path), varargin{:});
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
