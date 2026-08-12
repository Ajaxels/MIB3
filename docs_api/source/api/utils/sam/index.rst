sam — Segment-anything helpers
==============================

The ``+utils/+sam`` package holds the controller-independent helpers of the
interactive segment-anything tools (``segmentationSAM``, ``segmentationSAM2``).

Those tools read and write the layers in the block mode, i.e. only the part of
the dataset that is currently shown, and they segment an object with a series
of clicks. The state of the layers taken on the first click therefore has to
survive a zoom, a pan or a new seeded slice; this package describes the shown
block, re-maps a cached image between two blocks and serves the cached states
to the segmenters.

It also holds the post-processing applied to what the model returns, currently
the removal of the small low-confidence islands that appear beside the
segmented object.

.. currentmodule:: utils.sam

.. automodule:: utils.sam
   :members:
