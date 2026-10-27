/// Whether a locally stored row matches the cloud copy.
enum SyncStatus {
  /// Same as the cloud copy.
  synced,

  /// Changed on this device; waiting in the outbox to be sent.
  pending;

  static SyncStatus parse(Object? value) =>
      value == pending.name ? pending : synced;
}

/// Facebook-style emoji reactions, including dislike.
enum ReactionType {
  like('👍', 'Like'),
  love('❤️', 'Love'),
  haha('😆', 'Haha'),
  wow('😮', 'Wow'),
  sad('😢', 'Sad'),
  angry('😡', 'Angry'),
  dislike('👎', 'Dislike');

  const ReactionType(this.emoji, this.label);

  final String emoji;
  final String label;

  /// Reactions offered in the emoji picker, in display order.
  static const emojiReactions = [like, love, haha, wow, sad, angry, dislike];

  static ReactionType? tryParse(Object? value) {
    for (final type in values) {
      if (type.name == value) return type;
    }
    return null;
  }
}

enum MediaType {
  image,
  video;

  static MediaType? tryParse(Object? value) {
    for (final type in values) {
      if (type.name == value) return type;
    }
    return null;
  }
}

/// An uploaded image or video.
class MediaRef {
  const MediaRef({required this.url, required this.type});

  /// Public URL (posts) or storage path (chat).
  final String url;
  final MediaType type;
}

DateTime _parseDate(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '')?.toUtc() ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime? _tryParseDate(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toUtc();

final _hashtag = RegExp(r'#([^\s\p{P}]+)', unicode: true);

/// Hashtags in [text], lower-cased and without '#'. Mirrors the cloud trigger.
List<String> extractTags(String text) =>
    {for (final m in _hashtag.allMatches(text)) m.group(1)!.toLowerCase()}
        .toList();

class Post {
  const Post({
    required this.id,
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.content,
    required this.createdAt,
    this.groupId,
    this.media,
    this.tags = const [],
    this.sharedPostId,
    this.shared,
    this.updatedAt,
    this.syncStatus = SyncStatus.synced,
  });

  factory Post.fromMap(Map<String, Object?> map) {
    final mediaUrl = map['media_url'] as String?;
    final mediaType = MediaType.tryParse(map['media_type']);
    final shared = map['shared'] as Map?;
    return Post(
      sharedPostId: map['shared_post_id'] as String?,
      shared: shared == null
          ? null
          : Post.fromMap(Map<String, Object?>.from(shared)),
      id: map['id'] as String,
      userId: map['user_id'] as String,
      username: map['username']?.toString() ?? 'User',
      avatarUrl: map['avatar_url'] as String?,
      content: map['content']?.toString() ?? '',
      createdAt: _parseDate(map['created_at']),
      groupId: map['group_id'] as String?,
      media: mediaUrl != null && mediaType != null
          ? MediaRef(url: mediaUrl, type: mediaType)
          : null,
      tags: (map['tags'] as List?)?.cast<String>() ?? const [],
      updatedAt: _tryParseDate(map['updated_at']),
      syncStatus: SyncStatus.parse(map['sync_status']),
    );
  }

  final String id;
  final String userId;
  final String username;

  /// Author's current profile picture (from profiles, not stored on the row).
  final String? avatarUrl;
  final String content;
  final DateTime createdAt;
  final String? groupId;
  final MediaRef? media;
  final List<String> tags;

  /// Set when this post shares another post.
  final String? sharedPostId;

  /// The shared post, or null when it was deleted or is hidden from you.
  final Post? shared;
  final DateTime? updatedAt;
  final SyncStatus syncStatus;

  bool get isEdited => updatedAt != null;
  bool get isShare => sharedPostId != null;

  /// What a share should point at: re-sharing a share shares the original.
  Post get shareTarget => shared ?? this;

  /// Snapshot stored with a share so it displays offline.
  Map<String, Object?> toSharedSnapshot() => {
    'id': id,
    'user_id': userId,
    'username': username,
    'avatar_url': avatarUrl,
    'content': content,
    'created_at': createdAt.toIso8601String(),
    'media_url': media?.url,
    'media_type': media?.type.name,
  };
}

class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.content,
    required this.createdAt,
    this.parentId,
    this.media,
    this.updatedAt,
    this.syncStatus = SyncStatus.synced,
  });

  factory Comment.fromMap(Map<String, Object?> map) {
    final mediaUrl = map['media_url'] as String?;
    final mediaType = MediaType.tryParse(map['media_type']);
    return Comment(
      id: map['id'] as String,
      postId: map['post_id'] as String,
      userId: map['user_id'] as String,
      username: map['username']?.toString() ?? 'User',
      avatarUrl: map['avatar_url'] as String?,
      content: map['content']?.toString() ?? '',
      createdAt: _parseDate(map['created_at']),
      parentId: map['parent_id'] as String?,
      media: mediaUrl != null && mediaType != null
          ? MediaRef(url: mediaUrl, type: mediaType)
          : null,
      updatedAt: _tryParseDate(map['updated_at']),
      syncStatus: SyncStatus.parse(map['sync_status']),
    );
  }

  final String id;
  final String postId;
  final String userId;
  final String username;

  /// Author's current profile picture (from profiles, not stored on the row).
  final String? avatarUrl;
  final String content;

  /// The comment this one replies to (null for top-level comments).
  final String? parentId;
  final MediaRef? media;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final SyncStatus syncStatus;

  bool get isEdited => updatedAt != null;
}

/// A post as shown in a feed, with its counters and the viewer's reaction.
class FeedPost {
  const FeedPost({
    required this.post,
    required this.isMine,
    this.reactions = const {},
    this.comments = 0,
    this.myReaction,
  });

  final Post post;
  final bool isMine;
  final Map<ReactionType, int> reactions;
  final int comments;
  final ReactionType? myReaction;

  int get likes => reactions[ReactionType.like] ?? 0;
  int get dislikes => reactions[ReactionType.dislike] ?? 0;

  /// Reactions used on this post, most used first.
  List<ReactionType> get topEmoji {
    final used = reactions.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in used) e.key];
  }

  int get emojiTotal => reactions.values.fold(0, (sum, n) => sum + n);
}

/// Which posts a feed shows. Each scope is pulled and cached separately.
class FeedScope {
  const FeedScope.home() : kind = FeedKind.home, value = null;
  const FeedScope.group(String groupId)
    : kind = FeedKind.group,
      value = groupId;
  const FeedScope.user(String userId) : kind = FeedKind.user, value = userId;
  FeedScope.tag(String tag)
    : kind = FeedKind.tag,
      value = tag.replaceFirst('#', '').toLowerCase();

  /// Specific posts, e.g. saved posts or the post a notification is about.
  FeedScope.ids(Iterable<String> ids)
    : kind = FeedKind.ids,
      value = ids.join(',');

  final FeedKind kind;
  final String? value;

  List<String> get ids =>
      value == null || value!.isEmpty ? const [] : value!.split(',');

  bool matches(Map<String, Object?> post) => switch (kind) {
    FeedKind.home => post['group_id'] == null,
    FeedKind.group => post['group_id'] == value,
    FeedKind.user => post['user_id'] == value && post['group_id'] == null,
    FeedKind.tag => ((post['tags'] as List?) ?? const []).contains(value),
    FeedKind.ids => ids.contains(post['id']),
  };

  @override
  bool operator ==(Object other) =>
      other is FeedScope && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

enum FeedKind { home, group, user, tag, ids }

class SyncState {
  const SyncState({
    this.pendingChanges = 0,
    this.isSyncing = false,
    this.isOffline = false,
    this.lastError,
  });

  final int pendingChanges;
  final bool isSyncing;
  final bool isOffline;
  final String? lastError;

  SyncState copyWith({
    int? pendingChanges,
    bool? isSyncing,
    bool? isOffline,
    String? lastError,
    bool clearError = false,
  }) => SyncState(
    pendingChanges: pendingChanges ?? this.pendingChanges,
    isSyncing: isSyncing ?? this.isSyncing,
    isOffline: isOffline ?? this.isOffline,
    lastError: clearError ? null : lastError ?? this.lastError,
  );
}

// ---------------------------------------------------------------------------
// Online-only features
// ---------------------------------------------------------------------------

class Profile {
  const Profile({
    required this.id,
    required this.username,
    this.displayName,
    this.bio,
    this.avatarUrl,
    this.isPrivate = false,
    this.savedPublic = false,
  });

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
    id: map['id'] as String,
    username: map['username']?.toString() ?? 'user',
    displayName: (map['display_name'] as String?)?.trim().isNotEmpty == true
        ? map['display_name'] as String
        : null,
    bio: map['bio'] as String?,
    avatarUrl: map['profile_url'] as String?,
    isPrivate: map['is_private'] == true,
    savedPublic: map['saved_public'] == true,
  );

  final String id;
  final String username;
  final String? displayName;
  final String? bio;
  final String? avatarUrl;
  final bool isPrivate;

  /// Whether other people may see this user's saved posts.
  final bool savedPublic;

  String get name => displayName ?? username;
}

class ProfileStats {
  const ProfileStats({
    this.posts = 0,
    this.followers = 0,
    this.following = 0,
    this.requests = 0,
  });

  final int posts;
  final int followers;
  final int following;

  /// Pending follow requests (only counted for the viewer's own profile).
  final int requests;
}

enum FollowStatus { none, pending, accepted }

enum GroupKind {
  group('Group'),
  page('Page');

  const GroupKind(this.label);

  final String label;

  static GroupKind parse(Object? value) => value == 'page' ? page : group;
}

enum GroupRole {
  owner('Owner'),
  admin('Staff'),
  member('Member');

  const GroupRole(this.label);

  final String label;
}

class Group {
  const Group({
    required this.id,
    required this.name,
    required this.kind,
    required this.createdBy,
    this.description,
    this.avatarUrl,
    this.coverUrl,
    this.memberCount = 0,
    this.myRole,
    this.notifySetting,
  });

  factory Group.fromMap(Map<String, dynamic> map, {required String me}) {
    final members = (map['group_members'] as List?) ?? const [];
    GroupRole? role;
    bool? notify;
    var count = 0;
    for (final m in members) {
      final member = m as Map;
      if (member.containsKey('count')) {
        count = member['count'] as int;
      } else if (member['user_id'] == me) {
        role = GroupRole.values.asNameMap()[member['role']];
        notify = member['notify'] as bool?;
      }
    }
    return Group(
      id: map['id'] as String,
      name: map['name']?.toString() ?? '',
      description: map['description'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      coverUrl: map['cover_url'] as String?,
      kind: GroupKind.parse(map['kind']),
      createdBy: map['created_by'] as String,
      memberCount: count,
      myRole: role,
      notifySetting: notify,
    );
  }

  final String id;
  final String name;
  final String? description;

  /// Group profile picture and banner image.
  final String? avatarUrl;
  final String? coverUrl;
  final GroupKind kind;
  final String createdBy;
  final int memberCount;
  final GroupRole? myRole;

  /// My saved choice for new-post notifications; null means the default.
  final bool? notifySetting;

  /// Whether I get notified about new posts. Pages default to on, groups to
  /// off (they are busier). Mirrors notify_new_post() in the database.
  bool get notificationsOn =>
      isMember && (notifySetting ?? kind == GroupKind.page);

  bool get isMember => myRole != null;
  bool get isAdmin => myRole == GroupRole.owner || myRole == GroupRole.admin;
  bool get isOwner => myRole == GroupRole.owner;
  bool get canPost => kind == GroupKind.group ? isMember : isAdmin;
}

class GroupMember {
  const GroupMember({required this.profile, required this.role});

  final Profile profile;
  final GroupRole role;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.createdAt,
    this.media,
    this.isRead = false,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    final mediaUrl = map['media_url'] as String?;
    final mediaType = MediaType.tryParse(map['media_type']);
    return ChatMessage(
      id: map['id'].toString(),
      senderId: map['sender_id'] as String,
      receiverId: map['receiver_id'] as String,
      text: map['message']?.toString() ?? '',
      createdAt: _parseDate(map['created_at']),
      media: mediaUrl != null
          ? MediaRef(url: mediaUrl, type: mediaType ?? MediaType.image)
          : null,
      isRead: map['is_read'] == true,
    );
  }

  final String id;
  final String senderId;
  final String receiverId;
  final String text;
  final DateTime createdAt;

  /// Storage path in the private chat-media bucket.
  final MediaRef? media;
  final bool isRead;

  String partnerOf(String me) => senderId == me ? receiverId : senderId;
}

class Conversation {
  const Conversation({
    required this.partner,
    required this.lastMessage,
    this.unread = 0,
  });

  final Profile partner;
  final ChatMessage lastMessage;
  final int unread;
}

enum ReportReason {
  spam('Spam'),
  nudity('Nudity or sexual content'),
  violence('Violence'),
  harassment('Harassment or bullying'),
  hate('Hate speech'),
  falseInformation('False information'),
  other('Something else');

  const ReportReason(this.label);

  final String label;

  String get value => this == falseInformation ? 'false_information' : name;
}

enum ActivityType {
  follow,
  followRequest,
  followAccepted,
  friendPost,
  pagePost,
  groupPost,
  comment,
  reply,
  reaction,
  share;

  static ActivityType? parse(Object? value) => switch (value) {
    'comment' => comment,
    'reply' => reply,
    'reaction' => reaction,
    'share' => share,
    'follow' => follow,
    'follow_request' => followRequest,
    'follow_accepted' => followAccepted,
    'friend_post' => friendPost,
    'page_post' => pagePost,
    'group_post' => groupPost,
    _ => null,
  };
}

/// An entry on the notifications page.
class ActivityNotification {
  const ActivityNotification({
    required this.id,
    required this.type,
    required this.actor,
    required this.createdAt,
    this.postId,
    this.postPreview,
    this.groupId,
    this.groupName,
    this.groupAvatarUrl,
    this.reaction,
    this.isRead = false,
  });

  /// Returns null for unknown types (e.g. from a newer app version).
  static ActivityNotification? fromMap(Map<String, dynamic> map) {
    final type = ActivityType.parse(map['type']);
    final actor = map['actor'] as Map<String, dynamic>?;
    if (type == null || actor == null) return null;
    final post = map['post'] as Map<String, dynamic>?;
    final group = map['group'] as Map<String, dynamic>?;
    final content = (post?['content'] as String?)?.trim() ?? '';
    return ActivityNotification(
      id: map['id'] as String,
      type: type,
      actor: Profile.fromMap(actor),
      createdAt: _parseDate(map['created_at']),
      postId: map['post_id'] as String?,
      postPreview: content.isNotEmpty
          ? content
          : post?['media_type'] == 'video'
          ? 'a video'
          : post?['media_type'] == 'image'
          ? 'a photo'
          : null,
      groupId: map['group_id'] as String?,
      groupName: group?['name'] as String?,
      groupAvatarUrl: group?['avatar_url'] as String?,
      reaction: ReactionType.tryParse(map['reaction']),
      isRead: map['is_read'] == true,
    );
  }

  final String id;
  final ActivityType type;
  final Profile actor;
  final DateTime createdAt;
  final String? postId;
  final String? postPreview;
  final String? groupId;
  final String? groupName;
  final String? groupAvatarUrl;

  /// For reaction notifications: which emoji.
  final ReactionType? reaction;

  bool get isFromPage => type == ActivityType.pagePost;

  /// Who the notification shows: the page for page posts, else the person.
  String get displayName => isFromPage ? groupName ?? 'Page' : actor.name;
  String? get displayAvatarUrl => isFromPage ? groupAvatarUrl : actor.avatarUrl;
  final bool isRead;

  String get text => switch (type) {
    ActivityType.follow => '${actor.name} started following you.',
    ActivityType.followRequest => '${actor.name} requested to follow you.',
    ActivityType.followAccepted =>
      '${actor.name} accepted your follow request.',
    ActivityType.friendPost =>
      '${actor.name} posted'
          '${postPreview == null ? '.' : ': "${_short(postPreview!)}"'}',
    ActivityType.pagePost =>
      '${groupName ?? 'A page you follow'} posted'
          '${postPreview == null ? '.' : ': "${_short(postPreview!)}"'}',
    ActivityType.groupPost =>
      '${actor.name} posted in ${groupName ?? 'a group'}'
          '${postPreview == null ? '.' : ': "${_short(postPreview!)}"'}',
    ActivityType.comment => '${actor.name} commented on your post.',
    ActivityType.reply => '${actor.name} replied to your comment.',
    ActivityType.reaction =>
      '${actor.name} reacted ${reaction?.emoji ?? ''} to your post.'.replaceAll(
        '  ',
        ' ',
      ),
    ActivityType.share => '${actor.name} shared your post.',
  };

  /// Whether tapping it should open a post.
  bool get isAboutPost => switch (type) {
    ActivityType.follow ||
    ActivityType.followRequest ||
    ActivityType.followAccepted => false,
    _ => postId != null,
  };

  static String _short(String text) =>
      text.length > 80 ? '${text.substring(0, 80)}…' : text;
}

enum ReportStatus { pending, dismissed, removed }

/// A report on a group post, as seen by the group's owner/staff.
class GroupReport {
  const GroupReport({
    required this.id,
    required this.postId,
    required this.reason,
    required this.createdAt,
    required this.status,
    this.details,
    this.reporter,
    this.postAuthor,
    this.postContent,
    this.postMedia,
  });

  final String id;
  final String postId;
  final ReportReason reason;
  final String? details;
  final DateTime createdAt;
  final ReportStatus status;
  final Profile? reporter;
  final String? postAuthor;
  final String? postContent;
  final MediaRef? postMedia;

  static GroupReport fromMap(Map<String, dynamic> map, Profile? reporter) {
    final post = map['post'] as Map<String, dynamic>?;
    final mediaUrl = post?['media_url'] as String?;
    final mediaType = MediaType.tryParse(post?['media_type']);
    return GroupReport(
      id: map['id'].toString(),
      postId: map['post_id'] as String,
      reason: ReportReason.values.firstWhere(
        (r) => r.value == map['reason'],
        orElse: () => ReportReason.other,
      ),
      details: map['details'] as String?,
      createdAt: _parseDate(map['created_at']),
      status:
          ReportStatus.values.asNameMap()[map['status']] ??
          ReportStatus.pending,
      reporter: reporter,
      postAuthor: post?['username'] as String?,
      postContent: post?['content'] as String?,
      postMedia: mediaUrl != null && mediaType != null
          ? MediaRef(url: mediaUrl, type: mediaType)
          : null,
    );
  }
}
