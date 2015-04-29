#if LINUX
namespace Frida {
	public class QNXHostSessionBackend : Object, HostSessionBackend {
		private QNXHostSessionProvider local_provider;

		public async void start () {
			assert (local_provider == null);
			local_provider = new QNXHostSessionProvider ();
			provider_available (local_provider);
		}

		public async void stop () {
			assert (local_provider != null);
			provider_unavailable (local_provider);
			yield local_provider.close ();
			local_provider = null;
		}
	}

	public class QNXHostSessionProvider : Object, HostSessionProvider {
		public string name {
			get { return "Local System"; }
		}

		public ImageData? icon {
			get { return null; }
		}

		public HostSessionProviderKind kind {
			get { return HostSessionProviderKind.LOCAL_SYSTEM; }
		}

		private QNXHostSession host_session;

		public async void close () {
			if (host_session != null)
				yield host_session.close ();
			host_session = null;
		}

		public async HostSession create () throws Error {
			if (host_session != null)
				throw new Error.NOT_SUPPORTED ("may only create one HostSession");
			host_session = new QNXHostSession ();
			host_session.agent_session_closed.connect ((id, error) => this.agent_session_closed (id, error));
			return host_session;
		}

		public async AgentSession obtain_agent_session (AgentSessionId id) throws Error {
			if (host_session == null)
				throw new Error.NOT_SUPPORTED ("no such id");
			return yield host_session.obtain_agent_session (id);
		}
	}

	public class QNXHostSession : BaseDBusHostSession {
		public Gee.HashMap<uint, void *> instance_by_pid = new Gee.HashMap<uint, void *> ();

		private Qinjector injector = new Qinjector ();
		private QAgentDescriptor agent_desc;

		construct {
			var blob = Frida.Data.Agent.get_frida_agent_so_blob ();
			agent_desc = new QAgentDescriptor (blob.name, new MemoryInputStream.from_data (blob.data, null));
		}

		public override async void close () {
			yield base.close ();

			var uninjected_handler = injector.uninjected.connect ((id) => close.callback ());
			while (injector.any_still_injected ())
				yield;
			injector.disconnect (uninjected_handler);
			injector = null;
		}

		public override async Frida.HostProcessInfo[] enumerate_processes () throws Error {
			return System.enumerate_processes ();
		}

		public override async uint spawn (string path, string[] argv, string[] envp) throws Error {
			return _do_spawn (path, argv, envp);
		}

		public override async void resume (uint pid) throws Error {
			void * instance;
			bool instance_found = instance_by_pid.unset (pid, out instance);
			if (!instance_found)
				throw new Error.NOT_SUPPORTED ("no such pid");
			_resume_instance (instance);
			_free_instance (instance);
		}

		public override async void kill (uint pid) throws Error {
			void * instance;
			bool instance_found = instance_by_pid.unset (pid, out instance);
			if (instance_found)
				_free_instance (instance);
			System.kill (pid);
		}

		protected override async IOStream perform_attach_to (uint pid, out Object? transport) throws Error {
			PipeTransport.set_temp_directory (injector.temp_directory);
			PipeTransport t;
			Pipe stream;
			try {
				t = new PipeTransport ();
				stream = new Pipe (t.local_address);
			} catch (IOError stream_error) {
				throw new Error.PROCESS_GONE (stream_error.message);
			}
			yield injector.inject (pid, agent_desc, t.remote_address);
			transport = t;
			return stream;
		}

		public extern uint _do_spawn (string path, string[] argv, string[] envp) throws Error;
		public extern void _resume_instance (void * instance);
		public extern void _free_instance (void * instance);
	}
}
#endif
