"""Transport one unchanged unsigned simulator Build/Products between CI jobs.

Hashes are anchored in the producer job's outputs, never in an archive's own
claims. No extraction occurs until every tar header has passed safety checks.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import plistlib
import re
import shutil
import stat
import subprocess
import tarfile

RPAC_PATH = '/usr/lib/libRPAC.dylib'
HOST_INJECTION = '__TESTHOST__/Frameworks/libXCTestBundleInject.dylib'
PLATFORM_DIRECTORIES = {
    'DYLD_FRAMEWORK_PATH': '__PLATFORMS__/iPhoneSimulator.platform/Developer/Library/Frameworks',
    'DYLD_LIBRARY_PATH': '__PLATFORMS__/iPhoneSimulator.platform/Developer/usr/lib',
}
ENVIRONMENT_SECTIONS = {'EnvironmentVariables', 'TestingEnvironmentVariables', 'UITargetAppEnvironmentVariables'}


def require(value, message):
    if not value:
        raise ValueError(message)


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n', encoding='utf-8')


def environment():
    def output(*args):
        return subprocess.check_output(args, text=True).strip()
    return {'developerDirectory': output('xcode-select', '-p') if not os.environ.get('DEVELOPER_DIR')
            else os.environ['DEVELOPER_DIR'],
            'xcode': output('xcodebuild', '-version'),
            'sdkVersion': output('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'),
            'sdkBuildVersion': output('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-build-version'),
            'sdkPath': output('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'),
            'architecture': platform.machine(),
            'macOSVersion': output('sw_vers', '-productVersion'),
            'macOSBuildVersion': output('sw_vers', '-buildVersion'),
            'systemInjectionLibraries': {RPAC_PATH: system_injection_fingerprint()}}


def system_injection_fingerprint():
    """Only the OS library observed in original Xcode26.3 probe run41232876938.

    Its bytes are captured from the producer and anchored in needs.build's
    manifest hash, then compared on every consumer. No library is loaded here.
    """
    path = Path(RPAC_PATH)
    require(path.is_file() and not path.is_symlink() and str(path.resolve()) == RPAC_PATH,
            'Missing or linked observed system injection library')
    info = path.stat()
    mode = stat.S_IMODE(info.st_mode)
    require(info.st_uid == 0 and not mode & 0o7022, 'Unsafe system injection library owner/mode')
    architectures = sorted(subprocess.check_output(['xcrun', 'lipo', '-archs', str(path)], text=True).split())
    require(architectures == ['arm64e', 'x86_64'], 'Unobserved system injection library architectures')
    return {'realPath': RPAC_PATH, 'sha256': digest(path), 'size': info.st_size,
            'mode': mode, 'ownerUID': info.st_uid, 'architectures': architectures}


def validate_platform_directory(value, build_environment):
    require(value in PLATFORM_DIRECTORIES.values(), 'Unobserved Xcode platform directory')
    developer = Path(build_environment['developerDirectory'])
    target = developer / 'Platforms' / value[len('__PLATFORMS__/'):]
    require(target.is_dir() and target.resolve().is_relative_to(developer.resolve()),
            'Missing/escaping exact Xcode platform directory')


def product_path(value, products, host=None):
    if value.startswith('__TESTHOST__/'):
        require(host is not None, 'Missing test host for product placeholder')
        value = host + value[len('__TESTHOST__'):]
    require(value.startswith('__TESTROOT__/'), 'Nonrelocatable test product path')
    relative = value[len('__TESTROOT__/'):]
    require(relative and '\\' not in relative and ':' not in relative and '\0' not in relative and
            all(part not in ('', '.', '..') for part in relative.split('/')),
            'Missing/escaping or unsafe test product path: ' + value)
    target = products / relative
    require(target.resolve().is_relative_to(products.resolve()) and target.exists(),
            'Missing/escaping xctestrun product: ' + value)
    return target


def validate_environment_value(key, value, section, products, host, build_environment):
    if key == 'DYLD_INSERT_LIBRARIES':
        require(section in ('EnvironmentVariables', 'TestingEnvironmentVariables'),
                'Unobserved injection environment section')
        allowed = [RPAC_PATH]
        if section == 'TestingEnvironmentVariables':
            allowed.append(HOST_INJECTION + ':' + RPAC_PATH)
        require(value in allowed, 'Unobserved system/test injection library list')
        if value.startswith(HOST_INJECTION):
            require(product_path(HOST_INJECTION, products, host).is_file(), 'Missing original test injection library')
        return
    directory_keys = {'DYLD_FRAMEWORK_PATH', 'DYLD_LIBRARY_PATH', '__XPC_DYLD_FRAMEWORK_PATH',
                      '__XPC_DYLD_LIBRARY_PATH', '__XCODE_BUILT_PRODUCTS_DIR_PATHS'}
    if key in directory_keys:
        require(section in ('TestingEnvironmentVariables', 'UITargetAppEnvironmentVariables'),
                'Unobserved search-path environment section')
        components = value.split(':')
        require(all(components) and len(components) == len(set(components)), 'Empty/duplicate search-path component')
        for component in components:
            if component.startswith('__PLATFORMS__/'):
                require(section == 'TestingEnvironmentVariables' and PLATFORM_DIRECTORIES.get(key) == component,
                        'Unobserved Xcode search-path component')
                validate_platform_directory(component, build_environment)
            else:
                require(product_path(component, products, host).is_dir(), 'Search path must reference a product directory')
        return
    require(not key.startswith(('DYLD_', '__XPC_DYLD_', '__XCODE_')), 'Unobserved generated loader environment key')
    reject_external_string(value, key)


def reject_external_string(value, key):
    require(not value.startswith('/') and ':/' not in value and '\\' not in value and '\0' not in value
            and not re.search(r'[A-Za-z]:[\\/]', value)
            and not any(part in ('.', '..') for part in value.split('/'))
            and not any(token in value for token in ('__TESTROOT__', '__TESTHOST__', '__PLATFORMS__')),
            'Nonrelocatable xctestrun value: ' + key)


def validate_xctestrun_metadata(run, products, build_environment):
    targets = set()
    path_keys = {'TestBundlePath', 'TestHostPath', 'UITargetAppPath', 'DependentProductPaths'}

    def inspect(value, key='', host=None):
        if isinstance(value, dict):
            target_dictionary = 'TestBundlePath' in value and 'TestHostPath' in value
            if isinstance(value.get('TestHostPath'), str):
                raw_host = value['TestHostPath']
                product_path(raw_host, products)
                parts = raw_host.split('/')
                app_index = next((i for i, part in enumerate(parts) if part.endswith('.app')), None)
                require(app_index is not None, 'Original app test host required')
                host = '/'.join(parts[:app_index + 1])
            for field, child in value.items():
                if field in path_keys:
                    require((field == 'DependentProductPaths' and isinstance(child, list) and child
                             and all(isinstance(path, str) for path in child)) or
                            (field != 'DependentProductPaths' and isinstance(child, str)),
                            'Malformed original test product path field: ' + field)
                if field in ('BlueprintName', 'ProductModuleName') and isinstance(child, str):
                    targets.add(child)
                if field in ('AtharTests', 'AtharUITests'):
                    targets.add(field)
                if field in ENVIRONMENT_SECTIONS:
                    require(target_dictionary and isinstance(child, dict), 'Environment outside original test target')
                    for env_key, env_value in child.items():
                        require(isinstance(env_key, str) and env_key and '\0' not in env_key and '\\' not in env_key,
                                'Unsafe generated environment key')
                        require(isinstance(env_value, str), 'Generated environment values must be strings')
                        validate_environment_value(env_key, env_value, field, products, host, build_environment)
                else:
                    inspect(child, field, host)
        elif isinstance(value, list):
            for child in value:
                inspect(child, key, host)
        elif isinstance(value, str):
            if key in path_keys:
                product_path(value, products, host)
            else:
                reject_external_string(value, key)
    inspect(run)
    return targets


def preserve_diagnostics(products, producer, commit, run_id):
    """Save original inputs before environment checks, product validation or move.

    The producer directory is always uploaded by the existing workflow. Failure
    diagnostics remain there even when no transport archive can be produced.
    """
    output = producer / 'native-product-diagnostics'
    output.mkdir(parents=True, exist_ok=False)
    originals, values = [], []
    for index, path in enumerate(sorted(products.glob('*.xctestrun'))):
        require(path.is_file() and not path.is_symlink(), 'Generated xctestrun must be an original regular file')
        name = 'original-%d-' % index + path.name
        shutil.copyfile(path, output / name)
        originals.append({'file': name, 'sha256': digest(path), 'bytes': path.stat().st_size})
        try:
            def inspect(value, trail=()):
                if isinstance(value, dict):
                    for key, child in value.items(): inspect(child, trail + (str(key),))
                elif isinstance(value, list):
                    for i, child in enumerate(value): inspect(child, trail + (str(i),))
                elif isinstance(value, str) and (value.startswith(('/', '__')) or
                     any(part.endswith('EnvironmentVariables') for part in trail)):
                    values.append({'originalFile': name, 'plistPath': list(trail), 'value': value})
            inspect(plistlib.loads(path.read_bytes()))
        except Exception as error:
            values.append({'originalFile': name, 'parseError': type(error).__name__})
    write(output / 'originals.json', {'sourceCommit': commit, 'producerRunID': run_id, 'files': originals,
                                     'scope': 'ORIGINAL_PACK_INPUTS_NOT_TEST_OR_RELEASE_ACCEPTANCE'})
    write(output / 'generated-path-environment-values.json', values)
    try:
        actual_environment = environment()
        write(output / 'environment.json', actual_environment)
        return actual_environment, output
    except Exception as error:
        write(output / 'environment-error.json', {'type': type(error).__name__, 'error': str(error)})
        raise


def safe_name(name):
    path = PurePosixPath(name)
    require(name and '\\' not in name and not path.is_absolute()
            and all(part not in ('', '.', '..') for part in name.split('/'))
            and not re.match(r'^[A-Za-z]:', name), 'Unsafe archive path: ' + name)
    require(path.parts[0] in ('Build', 'producer'), 'Unexpected payload root: ' + name)
    return path


def safe_link(name, target):
    require(target and '\\' not in target and not PurePosixPath(target).is_absolute()
            and not re.match(r'^[A-Za-z]:', target), 'Unsafe symlink: ' + name)
    parts = list(PurePosixPath(name).parts[:-1])
    for part in target.split('/'):
        if part == '..':
            require(len(parts) > 2, 'Symlink escapes Products: ' + name)
            parts.pop()
        elif part not in ('', '.'):
            parts.append(part)
    require(parts[:2] == ['Build', 'Products'], 'Symlink outside Products: ' + name)


def inventory(folder):
    result = {}
    for path in sorted(folder.rglob('*')):
        name = path.relative_to(folder).as_posix()
        safe_name(name)
        mode = stat.S_IMODE(path.lstat().st_mode)
        require(not mode & 0o7000, 'Privileged file mode: ' + name)
        if path.is_symlink():
            target = os.readlink(path)
            safe_link(name, target)
            require(path.resolve().is_relative_to((folder / 'Build/Products').resolve())
                    and path.exists(), 'Dangling/escaping symlink: ' + name)
            result[name] = {'kind': 'symlink', 'target': target, 'mode': mode}
        elif path.is_dir():
            result[name] = {'kind': 'directory', 'mode': mode}
        else:
            require(path.is_file(), 'Special file: ' + name)
            result[name] = {'kind': 'file', 'mode': mode, 'size': path.stat().st_size,
                            'sha256': digest(path)}
    return result


def binary_architecture(path, architecture):
    require(subprocess.check_output(['xcrun', 'lipo', '-archs', str(path)], text=True).strip().split()
            == [architecture], 'Wrong executable architecture: ' + str(path))


def validate_products(folder, architecture, build_environment=None):
    products = folder / 'Build/Products'
    require(architecture == 'arm64', 'Requires the same standard arm64 macOS runner')
    runs = list(products.glob('*.xctestrun'))
    require(len(runs) == 1, 'Exactly one original generated xctestrun required')
    run = plistlib.loads(runs[0].read_bytes())
    targets = validate_xctestrun_metadata(run, products, build_environment or environment())
    require({'AtharTests', 'AtharUITests'} <= targets, 'Both original test bundles required')
    app = products / 'Release-iphonesimulator/Athar.app'
    required = [app, app / 'PlugIns/NoorWidgets.appex',
                app / 'qcf-v2-manifest.json', app / 'qcf-v4-manifest.json',
                app / 'recitation-word-script.json', app / 'RecitationModel', app / 'IndependentCTC']
    require(all(path.exists() for path in required), 'Missing full application, extension or resources')
    bundles = [path for path in products.rglob('*')
               if path.suffix in ('.app', '.appex', '.xctest') and path.is_dir()]
    require(any(path.name == 'AtharTests.xctest' for path in bundles) and
            any(path.name == 'AtharUITests.xctest' for path in bundles), 'Missing test bundles')
    for bundle in bundles:
        info = plistlib.loads((bundle / 'Info.plist').read_bytes())
        executable = info.get('CFBundleExecutable', '')
        require(executable and Path(executable).name == executable, 'Invalid bundle executable')
        path = bundle / executable
        require(path.is_file() and path.stat().st_mode & 0o111, 'Missing executable or execute mode')
        binary_architecture(path, architecture)
    return runs[0].relative_to(folder).as_posix()


def validate_build(folder):
    receipt = json.loads((folder / 'producer/commands.json').read_text())
    require(receipt == {'build': {'exitCode': 0, 'deadlineSeconds': 1200, 'log': 'build.txt'}},
            'Missing original successful bounded build receipt')
    events = [json.loads(line[len('NOOR_NATIVE_PROCESS '):])
              for line in (folder / 'producer/build.txt').read_text().splitlines()
              if line.startswith('NOOR_NATIVE_PROCESS ')]
    require(len(events) == 2 and [row.get('event') for row in events] == ['start', 'end']
            and all(row.get('stage') == 'BUILD' and row.get('deadlineSeconds') == 1200 for row in events)
            and events[-1].get('exitCode') == 0, 'Build log does not prove successful bounded build')


def pack(products, producer, output, commit, run_id):
    require(re.fullmatch('[0-9a-f]{40}', commit) and re.fullmatch('[1-9][0-9]*', run_id),
            'Full source commit and GitHub producer run ID required')
    require(not output.exists(), 'Refuse to overwrite producer artifact')
    env, diagnostics = preserve_diagnostics(products, producer, commit, run_id)
    output.mkdir(parents=True)
    # Stage by rename: the exact complete products tree, including links/modes,
    # never a hand-picked app or rewritten xctestrun.
    payload = output / 'payload'
    (payload / 'Build').mkdir(parents=True)
    shutil.move(str(products), str(payload / 'Build/Products'))
    shutil.copytree(producer, payload / 'producer')
    try:
        xctestrun = validate_products(payload, env['architecture'], env)
        validate_build(payload)
        files = inventory(payload)
        archive = output / 'native-products.tar.gz'
        with tarfile.open(archive, 'w:gz', dereference=False) as tar:
            for name in files:
                tar.add(payload / name, arcname=name, recursive=False)
    except Exception as error:
        write(diagnostics / 'pack-failure.json', {'type': type(error).__name__, 'error': str(error)})
        raise
    manifest = {'schemaVersion': 1, 'sourceCommit': commit, 'producerRunID': run_id,
                'configuration': 'Release', 'project': 'project-accounts.yml',
                'environment': env, 'xctestrun': xctestrun, 'files': files,
                'archiveSHA256': digest(archive)}
    write(output / 'manifest.json', manifest)
    return manifest


def load_manifest(artifact, commit, run_id, manifest_hash, archive_hash):
    require(re.fullmatch('[0-9a-f]{40}', commit) and re.fullmatch('[1-9][0-9]*', run_id),
            'Full expected source and producer run ID required')
    require(all(re.fullmatch('[0-9a-f]{64}', value) for value in (manifest_hash, archive_hash)),
            'Trusted producer hashes required')
    require(digest(artifact / 'manifest.json') == manifest_hash, 'Producer manifest hash mismatch')
    manifest = json.loads((artifact / 'manifest.json').read_text())
    require(manifest.get('schemaVersion') == 1 and manifest.get('sourceCommit') == commit
            and manifest.get('producerRunID') == run_id, 'Cross-source/run artifact rejected')
    require(manifest.get('configuration') == 'Release' and manifest.get('project') == 'project-accounts.yml',
            'Wrong native product configuration')
    require(manifest.get('archiveSHA256') == archive_hash, 'Producer archive binding mismatch')
    string_environment = {'developerDirectory', 'xcode', 'sdkVersion', 'sdkBuildVersion', 'sdkPath', 'architecture',
                          'macOSVersion', 'macOSBuildVersion'}
    expected_environment = string_environment | {'systemInjectionLibraries'}
    require(isinstance(manifest.get('environment'), dict) and
            set(manifest['environment']) == expected_environment and
            all(isinstance(manifest['environment'].get(key), str) and manifest['environment'][key]
                for key in string_environment),
            'Incomplete exact producer environment')
    libraries = manifest['environment']['systemInjectionLibraries']
    require(isinstance(libraries, dict) and set(libraries) == {RPAC_PATH}, 'Unobserved producer system library')
    library = libraries[RPAC_PATH]
    require(isinstance(library, dict) and set(library) == {'realPath', 'sha256', 'size', 'mode', 'ownerUID', 'architectures'}
            and library.get('realPath') == RPAC_PATH and isinstance(library.get('sha256'), str)
            and re.fullmatch('[0-9a-f]{64}', library['sha256']) and type(library.get('size')) is int and library['size'] > 0
            and type(library.get('mode')) is int and 0 <= library['mode'] <= 0o7777 and not library['mode'] & 0o7022
            and type(library.get('ownerUID')) is int and library['ownerUID'] == 0
            and library.get('architectures') == ['arm64e', 'x86_64'],
            'Incomplete/unsafe producer system injection fingerprint')
    require(manifest['environment']['architecture'] == 'arm64', 'Wrong producer architecture')
    require(isinstance(manifest.get('files'), dict) and manifest['files'], 'Missing full product inventory')
    run = manifest.get('xctestrun', '')
    require(isinstance(run, str) and safe_name(run).parts[:2] == ('Build', 'Products')
            and run.endswith('.xctestrun') and run in manifest['files'], 'Missing original xctestrun binding')
    return manifest


def unpack(artifact, destination, commit, run_id, manifest_hash, archive_hash):
    manifest = load_manifest(artifact, commit, run_id, manifest_hash, archive_hash)
    require(environment() == manifest['environment'], 'Exact Xcode/SDK/architecture mismatch')
    archive = artifact / 'native-products.tar.gz'
    require(digest(archive) == archive_hash, 'Producer archive hash mismatch')
    require(not destination.exists(), 'Refuse to merge or overwrite native products')
    files = manifest['files']
    with tarfile.open(archive, 'r:gz') as tar:
        members = tar.getmembers()
        require(len(members) == len(files) and len({row.name for row in members}) == len(members),
                'Duplicate or missing archive member')
        symlinks = {row.name for row in members if row.issym()}
        for row in members:
            name = safe_name(row.name)
            require(row.name in files and not row.mode & 0o7000, 'Unexpected member or unsafe mode')
            require(row.type in (tarfile.REGTYPE, tarfile.AREGTYPE, tarfile.DIRTYPE, tarfile.SYMTYPE)
                    and not row.sparse, 'Unsupported special archive member')
            require(not any('/'.join(name.parts[:i]) in symlinks for i in range(1, len(name.parts))),
                    'Archive member beneath a symlink')
            expected = files[row.name]
            kind = 'directory' if row.isdir() else 'file' if row.isfile() else 'symlink' if row.issym() else None
            require(kind == expected['kind'] and row.mode == expected['mode'], 'Archive type/mode mismatch')
            if row.issym():
                safe_link(row.name, row.linkname)
                require(row.linkname == expected['target'], 'Symlink target mismatch')
            elif row.isfile():
                require(row.size == expected['size'], 'Archive size mismatch')
                with tar.extractfile(row) as stream:
                    require(hashlib.file_digest(stream, 'sha256').hexdigest() == expected['sha256'],
                            'Archive file hash mismatch')
        destination.mkdir(parents=True)
        # All names, link targets, member types and bytes validated first.
        tar.extractall(destination, members=members, filter='fully_trusted')
    require(inventory(destination) == files, 'Extracted full product inventory mismatch')
    require(validate_products(destination, manifest['environment']['architecture'], manifest['environment']) == manifest['xctestrun'],
            'Original xctestrun changed')
    validate_build(destination)
    return manifest


def verify_evidence(folder, commit, env=None):
    """Offline evidence check, including trusted job-output anchors and real log."""
    binding = json.loads((folder / 'native-product-binding.json').read_text())
    manifest = load_manifest(folder, commit, binding['producerRunID'], binding['manifestSHA256'],
                             binding['archiveSHA256'])
    if env is not None:
        require(env['GITHUB_RUN_ID'] == binding['producerRunID']
                and env['NATIVE_MANIFEST_SHA256'] == binding['manifestSHA256']
                and env['NATIVE_ARCHIVE_SHA256'] == binding['archiveSHA256'], 'Untrusted producer binding')
    require((folder / 'xcode.txt').read_text().strip() == manifest['environment']['xcode'],
            'Evidence uses a different Xcode')
    for name in ('build.txt', 'commands.json', 'project-generation.txt'):
        path = folder / ('producer-commands.json' if name == 'commands.json' else name)
        require(digest(path) == manifest['files']['producer/' + name]['sha256'],
                'Original producer receipt changed: ' + name)
    require(binding.get('verifiedBeforeTesting') is True and binding.get('verifiedAfterTesting') is True,
            'Product integrity not verified before and after testing')
    return manifest


def main():
    parser = argparse.ArgumentParser(__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    packer = sub.add_parser('pack')
    packer.add_argument('--products', type=Path, required=True)
    packer.add_argument('--producer', type=Path, required=True)
    packer.add_argument('--output', type=Path, required=True)
    for action in ('unpack', 'check', 'select'):
        command = sub.add_parser(action)
        command.add_argument('--artifact', type=Path, required=True)
        if action != 'select':
            command.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    commit, run_id = os.environ['GITHUB_SHA'], os.environ['GITHUB_RUN_ID']
    if args.action == 'pack':
        manifest = pack(args.products, args.producer, args.output, commit, run_id)
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
            output.write('manifest-sha256=' + digest(args.output / 'manifest.json') + '\n')
            output.write('archive-sha256=' + manifest['archiveSHA256'] + '\n')
            output.write('producer-run-id=' + run_id + '\n')
        return
    manifest_hash, archive_hash = os.environ['NATIVE_MANIFEST_SHA256'], os.environ['NATIVE_ARCHIVE_SHA256']
    manifest = load_manifest(args.artifact, commit, run_id, manifest_hash, archive_hash)
    if args.action == 'select':
        developer = manifest['environment']['developerDirectory']
        require(re.fullmatch(r'/Applications/Xcode[^/\r\n]*\.app/Contents/Developer', developer),
                'Unsafe producer Xcode location')
        print('DEVELOPER_DIR=' + developer)
        return
    if args.action == 'unpack':
        unpack(args.artifact, args.destination, commit, run_id, manifest_hash, archive_hash)
    else:
        require(environment() == manifest['environment'], 'Exact Xcode/SDK/architecture mismatch')
        require(inventory(args.destination) == manifest['files'], 'Native products modified during testing')
    print(args.destination / manifest['xctestrun'])


if __name__ == '__main__':
    main()
