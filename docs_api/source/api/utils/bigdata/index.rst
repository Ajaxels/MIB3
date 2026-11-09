bigdata - Processing of BigData images
======================================

The ``+utils/+bigdata`` package holds the headless engine behind the BigData mode
of the Image tools: a pyramid level of a BigData image is processed in bands of
rows with a halo and written to a new OME-Zarr store. Tools that need a statistic
of the whole slice (a threshold, a mean and standard deviation) first collect it
from evenly spaced stripes of chunk rows (``sampleStripes``, ``sliceHistograms``).
The panel and the run in a tool window are :class:`controllers.BigDataOptions`.

.. currentmodule:: utils.bigdata

.. automodule:: utils.bigdata
   :members:
