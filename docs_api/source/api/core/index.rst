core — Core Data Classes
========================

.. currentmodule:: core

The ``+core`` package contains all data-holding classes.  A
:class:`core.MibDataset` instance represents one open dataset and owns
the image, label, mask, selection, annotation, and line-tracing layers.

Dataset and image layers
------------------------

.. toctree::
   :maxdepth: 1

   MibDataset
   MibImage
   MibVirtualImage

Label layers
------------

.. toctree::
   :maxdepth: 1

   MibLabels
   MibLabels63

Overlays and annotations
------------------------

.. toctree::
   :maxdepth: 1

   Annotations
   Lines3D
   RoiRegion

Supporting classes
------------------

.. toctree::
   :maxdepth: 1

   MibBackup
   ChildView
   MibIconCache
   PoolWaitbar
   ToggleEventData
