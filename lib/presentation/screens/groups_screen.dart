import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../data/repository_scope.dart';
import '../navigation.dart';
import '../widgets/common_widgets.dart';

/// Lists groups and pages: the ones you belong to and ones to discover.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final _search = TextEditingController();
  Future<List<Group>>? _future;
  Timer? _debounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<List<Group>> _load() =>
      RepositoryScope.servicesOf(context).groups
          .listGroups(query: _search.text);

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _create() async {
    final group = await showGroupForm(context);
    if (group != null && mounted) {
      _reload();
      await openGroup(context, group.id);
      if (mounted) _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Groups & Pages',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: kMainText,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _create,
                    style: FilledButton.styleFrom(backgroundColor: kGreen),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 400), _reload);
                },
                decoration: InputDecoration(
                  hintText: 'Search groups and pages',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: kCardWhite,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const TabBar(
                labelColor: kGreen,
                indicatorColor: kGreen,
                tabs: [
                  Tab(text: 'My groups'),
                  Tab(text: 'Discover'),
                ],
              ),
              Expanded(
                child: FutureBuilder<List<Group>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return ErrorRetry(
                        message: errorMessage(snapshot.error!),
                        onRetry: _reload,
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(color: kGreen),
                      );
                    }
                    final groups = snapshot.data!;
                    return TabBarView(
                      children: [
                        _GroupList(
                          groups: groups.where((g) => g.isMember).toList(),
                          empty: "You haven't joined any groups yet.",
                          onChanged: _reload,
                        ),
                        _GroupList(
                          groups: groups.where((g) => !g.isMember).toList(),
                          empty: 'No other groups found.',
                          onChanged: _reload,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupList extends StatelessWidget {
  const _GroupList({
    required this.groups,
    required this.empty,
    required this.onChanged,
  });

  final List<Group> groups;
  final String empty;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: kGreen,
      onRefresh: () async => onChanged(),
      child: groups.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 60),
                Center(
                  child: Text(empty, style: TextStyle(color: kSecondaryText)),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final group = groups[index];
                return GroupTile(
                  group: group,
                  onTap: () async {
                    await openGroup(context, group.id);
                    onChanged();
                  },
                );
              },
            ),
    );
  }
}

class GroupTile extends StatelessWidget {
  const GroupTile({super.key, required this.group, required this.onTap});

  final Group group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCardWhite,
      borderRadius: BorderRadius.circular(20),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        leading: GroupIcon(group: group),
        title: Text(
          group.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${group.kind.label} · ${group.memberCount} '
          '${group.kind == GroupKind.page ? 'followers' : 'members'}'
          '${group.myRole == GroupRole.owner ? ' · Owner' : ''}',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class GroupIcon extends StatelessWidget {
  const GroupIcon({super.key, required this.group, this.size = 44});

  final Group group;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isPage = group.kind == GroupKind.page;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isPage ? const Color(0xFFE8EEFF) : kPaleGreen,
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(
        isPage ? Icons.flag_rounded : Icons.groups_rounded,
        color: isPage ? const Color(0xFF3B5BDB) : kGreen,
        size: size / 2,
      ),
    );
    if (group.avatarUrl == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 3),
      child: Image.network(
        group.avatarUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// Create (no [group]) or edit a group/page. Returns the saved group.
Future<Group?> showGroupForm(BuildContext context, {Group? group}) {
  final services = RepositoryScope.servicesOf(context);
  return showDialog<Group>(
    context: context,
    builder: (_) => _GroupForm(
      group: group,
      pickImage: () => services.media.pick(MediaType.image),
      onSave: (name, description, kind, avatar, cover) async {
        // Pictures are uploaded first; only their URLs are stored.
        final avatarUrl = avatar == null
            ? null
            : await services.media.uploadAvatar(avatar);
        final coverUrl = cover == null
            ? null
            : await services.media.uploadAvatar(cover);
        if (group == null) {
          final created = await services.groups.createGroup(
            name: name,
            description: description,
            kind: kind,
          );
          if (avatarUrl == null && coverUrl == null) return created;
          return services.groups.updateGroup(
            created.id,
            name: name,
            description: description,
            avatarUrl: avatarUrl,
            coverUrl: coverUrl,
          );
        }
        return services.groups.updateGroup(
          group.id,
          name: name,
          description: description,
          avatarUrl: avatarUrl,
          coverUrl: coverUrl,
        );
      },
    ),
  );
}

class _GroupForm extends StatefulWidget {
  const _GroupForm({
    required this.group,
    required this.onSave,
    required this.pickImage,
  });

  final Group? group;
  final Future<Group> Function(
    String name,
    String description,
    GroupKind kind,
    XFile? avatar,
    XFile? cover,
  )
  onSave;
  final Future<XFile?> Function() pickImage;

  @override
  State<_GroupForm> createState() => _GroupFormState();
}

class _GroupFormState extends State<_GroupForm> {
  late final _name = TextEditingController(text: widget.group?.name ?? '');
  late final _description = TextEditingController(
    text: widget.group?.description ?? '',
  );
  late GroupKind _kind = widget.group?.kind ?? GroupKind.group;
  XFile? _avatar;
  XFile? _cover;
  Uint8List? _avatarBytes;
  Uint8List? _coverBytes;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final group = await widget.onSave(
        _name.text,
        _description.text,
        _kind,
        _avatar,
        _cover,
      );
      if (mounted) Navigator.of(context).pop(group);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorMessage(error);
        });
      }
    }
  }

  Future<void> _pick({required bool cover}) async {
    try {
      final file = await widget.pickImage();
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        if (cover) {
          _cover = file;
          _coverBytes = bytes;
        } else {
          _avatar = file;
          _avatarBytes = bytes;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    }
  }

  /// Banner with the group picture overlapping its bottom-left corner.
  Widget _pictures() {
    final group = widget.group;
    final ImageProvider? coverImage = _coverBytes != null
        ? MemoryImage(_coverBytes!)
        : group?.coverUrl != null
        ? NetworkImage(group!.coverUrl!)
        : null;
    final ImageProvider? avatarImage = _avatarBytes != null
        ? MemoryImage(_avatarBytes!)
        : group?.avatarUrl != null
        ? NetworkImage(group!.avatarUrl!)
        : null;
    return SizedBox(
      height: 130,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            onTap: _saving ? null : () => _pick(cover: true),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 100,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFEDEFF3),
                borderRadius: BorderRadius.circular(14),
                image: coverImage == null
                    ? null
                    : DecorationImage(image: coverImage, fit: BoxFit.cover),
              ),
              alignment: Alignment.topRight,
              padding: const EdgeInsets.all(6),
              child: const _PictureBadge(label: 'Banner'),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 0,
            child: InkWell(
              onTap: _saving ? null : () => _pick(cover: false),
              customBorder: const CircleBorder(),
              child: CircleAvatar(
                radius: 32,
                backgroundColor: kCardWhite,
                child: CircleAvatar(
                  radius: 29,
                  backgroundColor: kPaleGreen,
                  backgroundImage: avatarImage,
                  child: avatarImage == null
                      ? const Icon(Icons.add_a_photo_outlined, color: kGreen)
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.group != null;
    return AlertDialog(
      title: Text(editing ? 'Edit ${_kind.label.toLowerCase()}' : 'Create'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _pictures(),
              const SizedBox(height: 12),
              if (!editing) ...[
                SegmentedButton<GroupKind>(
                  segments: const [
                    ButtonSegment(
                      value: GroupKind.group,
                      icon: Icon(Icons.groups_rounded),
                      label: Text('Group'),
                    ),
                    ButtonSegment(
                      value: GroupKind.page,
                      icon: Icon(Icons.flag_rounded),
                      label: Text('Page'),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: _saving
                      ? null
                      : (value) => setState(() => _kind = value.first),
                ),
                const SizedBox(height: 6),
                Text(
                  _kind == GroupKind.group
                      ? 'Every member can post.'
                      : 'Only you and admins can post; others follow.',
                  style: TextStyle(color: kSecondaryText, fontSize: 12),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _name,
                enabled: !_saving,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _description,
                enabled: !_saving,
                maxLength: 500,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Description',
                  border: const OutlineInputBorder(),
                  errorText: _error,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text(editing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

class _PictureBadge extends StatelessWidget {
  const _PictureBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_camera_outlined, size: 14, color: kWhite),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: kWhite, fontSize: 12)),
        ],
      ),
    );
  }
}
