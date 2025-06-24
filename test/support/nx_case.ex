defmodule Nx.Case do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      import Nx.Defn
      import Nx.Case
    end
  end

  setup config do
    Nx.Defn.default_options(compiler: test_compiler())
    Nx.global_default_backend(test_backend())
    Process.register(self(), config.test)
    :ok
  end

  def test_compiler do
    cond do
      System.get_env("USE_EXLA") -> EXLA
      System.get_env("USE_EMLX") -> EMLX
      true -> Nx.Defn.Evaluator
    end
  end

  def test_backend do
    cond do
      System.get_env("USE_EXLA") -> EXLA.Backend
      System.get_env("USE_EMLX") -> EMLX.Backend
      true -> Nx.BinaryBackend
    end
  end
end
