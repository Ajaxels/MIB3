io — Image I/O
==============

The ``+io`` package implements a factory-based I/O pipeline:

.. code-block:: text

   ExtensionRegistryLoad  →  LoaderFactory.create()  →  loader
                                                         ├─ loadMetadata()
                                                         └─ loadImages()

   SaverFactory.create()  →  saver

.. currentmodule:: io

Factory functions
-----------------

.. autofunction:: ExtensionRegistryLoad

.. autofunction:: LoaderFactory

.. autofunction:: SaverFactory

.. autofunction:: loadImagesWrapper

.. autofunction:: mibImage2mrc

Loaders and savers
------------------

.. toctree::
   :maxdepth: 1

   loaders/index
   savers/index

Format sub-packages
-------------------

.. toctree::
   :maxdepth: 1

   AmiraMesh
   BioFormats
   Fiji
   HDF5
   imaris
   IMOD
   NRRD
