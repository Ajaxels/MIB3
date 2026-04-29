controllers — UI Controllers
============================

.. currentmodule:: controllers

The ``+controllers`` package contains all UI controller classes.
:class:`controllers.MibController` is the root controller; it owns all
sub-controllers listed below.

Main controllers
----------------

.. toctree::
   :maxdepth: 1

   MibController
   MibRibbon
   MibImageDocument

Panel controllers
-----------------

.. toctree::
   :maxdepth: 1

   MibActiveDataset
   MibDirContents
   MibSegmentation
   MibSelection
   MibRoi
   MibStatusBar
   MibQuickAccessBar

Dataset tool dialogs
--------------------

.. toctree::
   :maxdepth: 1

   CropDataset
   CropObjects
   ResampleDataset
   DisplayAdjust
   BoundingBox

Segmentation tool dialogs
-------------------------

.. toctree::
   :maxdepth: 1

   Annotations
   Lines3dDialog
   Quantification
   QuantificationProperties

Deep learning
-------------

.. toctree::
   :maxdepth: 1

   MibDeep

Preferences and utilities
-------------------------

.. toctree::
   :maxdepth: 1

   BatchProcessing
   Preferences
   WelcomeTips
