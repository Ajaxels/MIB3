classdef BioFormatsVirtualLoader < handle
    % classdef BioFormatsVirtualLoader < handle
    % On-demand plane reader for MIB3 BioFormats virtual datasets.
    %
    % Wraps a single microscopy file accessible via the Bio-Formats library.
    % A loci.formats.Memoizer reader is opened lazily on the first readPlane
    % call and kept open for the lifetime of the loader, avoiding the
    % overhead of re-opening the reader for every z-slice and time-point.
    %
    % Call close() (or let closeVirtualDataset delete the loader) to
    % release the file handle when the virtual dataset is closed.
    %
    % Unlike the batch loaders in +io/+loaders/ this class does NOT
    % implement BaseImageLoader — it is stateful and designed for repeated
    % single-plane reads rather than single full-dataset loads.
    %
    % Usage example:
    % @code
    % loader = io.loaders.BioFormatsVirtualLoader('/data/stack.czi', 0, tempdir);
    % planes = loader.readPlane([1 512], [1 512], 5, [1 2], 0, 'uint16');
    % % planes is [512, 512, 2] — one tile per requested channel
    % loader.close();
    % @endcode

    properties (SetAccess = private)
        filename
        % [char] full path to the BioFormats-readable file
        seriesIndex
        % [numeric] 0-based series index (Virtual.seriesName{fileIdx} - 1)
        memoDir
        % [char] directory for the BioFormats Memoizer memo files
        reader
        % loci.formats.Memoizer Java object; [] until openReader() is called
    end

    methods
        function obj = BioFormatsVirtualLoader(filename, seriesIndex, memoDir)
            % obj = BioFormatsVirtualLoader(filename, seriesIndex, memoDir)
            % Constructor
            %
            % Parameters:
            % filename    : [char] full path to the BioFormats-readable file
            % seriesIndex : [numeric] 0-based series index
            % memoDir     : [char] directory for BioFormats Memoizer memo files

            obj.filename    = filename;
            obj.seriesIndex = seriesIndex;
            obj.memoDir     = memoDir;
            obj.reader      = [];
        end

        function planes = readPlane(obj, Ylim, Xlim, planeId, colChannel, timepoint, dataClass)
            % planes = readPlane(obj, Ylim, Xlim, planeId, colChannel, timepoint, dataClass)
            % Read one XY tile across the requested colour channels from a single z/t plane.
            %
            % The Bio-Formats reader is opened on the first call and reused
            % on all subsequent calls to this loader.
            %
            % Parameters:
            % Ylim       : [ymin ymax] pixel range (1-based, inclusive)
            % Xlim       : [xmin xmax] pixel range (1-based, inclusive)
            % planeId    : [numeric] 1-based z-plane index within this file/series
            % colChannel : [1 x nC] vector of 1-based colour channel indices
            % timepoint  : [numeric] 0-based time-point index (as used by getIndex)
            % dataClass  : [char] output class, e.g. 'uint8' or 'uint16'
            %
            % Return values:
            % planes : [nY, nX, nC] array — one slice per requested channel

            if isempty(obj.reader)
                obj.openReader();
            end

            nY = Ylim(2) - Ylim(1) + 1;
            nX = Xlim(2) - Xlim(1) + 1;
            nC = numel(colChannel);
            planes = zeros([nY, nX, nC], dataClass);

            for ci = 1:nC
                iPlane = obj.reader.getIndex(planeId - 1, colChannel(ci) - 1, timepoint) + 1;
                cPlane = bfGetPlane(obj.reader, iPlane, Xlim(1), Ylim(1), nX, nY);

                % Bio-Formats may return int8 for unsigned 8-bit data; fix sign
                if isa(cPlane, 'int8')
                    cPlane = int16(cPlane);
                    cPlane(cPlane < 0) = cPlane(cPlane < 0) + 256;
                end

                planes(:, :, ci) = cast(cPlane, dataClass);
            end
        end

        function close(obj)
            % close(obj)
            % Close the Bio-Formats reader and release the file handle.
            % Safe to call multiple times.

            if ~isempty(obj.reader)
                try
                    obj.reader.close();
                catch
                    % reader may already be closed; ignore
                end
                obj.reader = [];
            end
        end

        function delete(obj)
            % delete(obj)
            % Destructor — closes the reader when the object is destroyed.

            obj.close();
        end
    end

    methods (Access = private)
        function openReader(obj)
            % openReader(obj)
            % Open the Bio-Formats Memoizer reader and select the series.
            % Called lazily on the first readPlane call.

            obj.reader = loci.formats.Memoizer(bfGetReader(), 0, java.io.File(obj.memoDir));
            obj.reader.setId(obj.filename);
            obj.reader.setSeries(obj.seriesIndex);
        end
    end
end
