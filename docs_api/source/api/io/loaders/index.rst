Loaders
=======

Image-format loaders implement the :class:`io.loaders.BaseImageLoader`
interface.  Each loader provides ``loadMetadata()`` and ``loadImages()``.

Standard loaders
----------------

.. toctree::
   :maxdepth: 1

   AmiraMeshLoader
   BioFormatsStdLoader
   HDF5NoHeaderLoader
   HDF5HeaderLoader
   ImodLoader
   ImreadLoader
   MatModelLoader
   MibImgLoader
   NrrdLoader
   VideoReaderLoader

Virtual loaders
---------------

.. toctree::
   :maxdepth: 1

   BioFormatsVirtualLoader
   BioFormatsVirtualSetupLoader
   HDF5VirtualLoader
   HDF5VirtualSetupLoader
   Zarr2VirtualLoader
   Zarr2VirtualSetupLoader
   Zarr3VirtualLoader
   Zarr3VirtualSetupLoader

Shared helpers
--------------

.. toctree::
   :maxdepth: 1

   OmeZarrMetadataUtils

Base class
----------

.. toctree::
   :maxdepth: 1

   BaseImageLoader
