import '../../../../domain/entities/online_gallery.dart';

abstract class GalleryAdapter {
  Future<OnlineGalleryPage> search(OnlineGalleryQuery query);
  Future<OnlineGalleryItem> detail(OnlineGalleryItem item,
      {bool safeOnly = true});
}
