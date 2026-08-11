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

Remote stores
-------------

``RemoteStore`` holds the URL and object-store plumbing shared by the remote
OME-Zarr paths: it recognises the common S3 URL spellings, rewrites ``s3://``
into an anonymous HTTPS URL, enumerates the children of a prefix through the S3
``ListObjectsV2`` API, and fetches small metadata files. It knows nothing about
Zarr itself.

The ``amazonaws.com`` patterns in ``parse`` exist only to tell Amazon's two
spellings apart - virtual-host style puts the bucket in the host, path style puts
it in the path. They are not what makes a store listable: any other host is read
as path style with the endpoint taken from the URL, which is what reaches MinIO
and Ceph deployments addressed as ``https://HOST/BUCKET/KEY``. Such a host
is flagged ``parse(url).flavour == 's3compatible'`` to mark the guess as
unconfirmed; one that does not answer the API simply returns an empty listing,
and callers fall back to an explicit user-supplied path.

.. autofunction:: RemoteStore

Chunk cache
-----------

``io.zarr.ChunkCache`` is an in-memory LRU of decoded Zarr chunks, shared by
``io.loaders.Zarr2VirtualLoader`` and ``io.loaders.Zarr3VirtualLoader``. It works
in Zarr's declared C-order index space and knows nothing about OME-Zarr,
pyramids, MIB axis conventions or which engine produced the chunks, which is what
lets one implementation serve both formats and both backends.

It exists because a chunk is the smallest unit a store will hand over, and
published volumes are routinely chunked for 3D block access - ``[64, 128, 128]``
is typical, so a chunk carries 64 slices. Without the cache, showing one plane
fetches all 64 and discards 63, and the next slice re-fetches the identical
chunks. Missing chunks of one request are fetched in a single call over their
bounding box, never one call per chunk, because the engines fetch the chunks of
one request concurrently.

.. currentmodule:: io.zarr

.. autofunction:: ChunkCache

.. currentmodule:: io

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
   HDF5
   imaris
   IMOD
   NRRD
