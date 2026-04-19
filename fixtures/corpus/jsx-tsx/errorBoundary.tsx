/** @jsxImportSource ./ */

const Fallback = () => <div>Out Of Service</div>;

export const Example = () => {
  const html = (
    <ErrorBoundary fallback={<Fallback />}>
      <Suspense fallback={<div>Loading...</div>}>
        <Component error={true} />
      </Suspense>
    </ErrorBoundary>
  );

  return (
    <>
      <div>{html}</div>
      <ErrorBoundary fallbackRender={() => Promise.resolve('< error >')}>
        <Component error={true} />
      </ErrorBoundary>
    </>
  );
};
