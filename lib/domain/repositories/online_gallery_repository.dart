import '../entities/online_gallery.dart';

abstract class OnlineGalleryRepository {
  Future<OnlineGalleryPage> search(OnlineGalleryQuery query);
  Future<OnlineGalleryItem> detail(OnlineGalleryItem item,
      {bool safeOnly = true});
  Future<List<OnlineGalleryItem>> favorites();
  Future<void> setFavorite(OnlineGalleryItem item, bool value);
  Future<OnlineGalleryQuery?> loadLastQuery();
  Future<void> saveQuery(OnlineGalleryQuery query);
  Future<String?> previewPath(OnlineGalleryItem item, OnlineGalleryMedia media);
  Future<OnlineGalleryDownloadResult> download(
      OnlineGalleryItem item, List<OnlineGalleryMedia> media);
  Future<void> saveStyle(OnlineGalleryItem item);
  Future<void> openSource(OnlineGalleryItem item);
  Future<void> clearCache();
  Future<bool> hasGelbooruCredentials();
  Future<void> setGelbooruCredentials(OnlineGalleryCredentials credentials);
}
