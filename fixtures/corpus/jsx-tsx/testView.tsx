type Props = {
  test: ISimulationTest;
  runner: SimulationRunner;
  runnerOptions: RunnerOptions;
  nesExternalOptions: NesExternalOptions;
  testSource: TestSourceValue;
  displayOptions: DisplayOptions;
};

export const TestView = mobxlite.observer(({ test, runner, runnerOptions, nesExternalOptions, testSource, displayOptions }: Props) => {
  const [isTestRunOpen, setIsTestRunOpen] = React.useState(new Array(test.runnerStatus?.runs.length).fill(test.runnerStatus?.runs.length === 1 ? true : false));
  const testItemRefs = React.useRef<HTMLDivElement[]>([]);

  const updateNth = (n: number, value: boolean) => {
    const copy = Array.from(isTestRunOpen);
    copy[n] = value;
    setIsTestRunOpen(copy);
  };

  return (
    <TreeItem itemType={'branch'} className='test-runs-container'>
      <TreeItemLayout
        iconBefore={<StatusIcon runner={runner} runnerOptions={runnerOptions} nesExternalOptions={nesExternalOptions} testSource={testSource} test={test} />}
        iconAfter={test.runnerStatus && <RunsSummaryBadge runs={test.runnerStatus.runs} />}
      >
        <Text>{test.suiteName ? test.name.replace(test.suiteName, '') : test.name}</Text>
      </TreeItemLayout>
      <Tree>
        {
          test.runnerStatus === undefined
            ? (
                <TreeItem itemType='leaf'>
                  <TreeItemLayout> Test doesn't have run info. </TreeItemLayout>
                </TreeItem>
              )
            : <>
                {test.runnerStatus.runs.map((run, idx) => {
                  const key = `${test.name}-${idx}`;
                  return (
                    <div key={key} ref={el => testItemRefs.current[idx] = el!}>
                      <TreeItem
                        itemType='branch'
                        open={isTestRunOpen[idx]}
                        onOpenChange={() => updateNth(idx, !isTestRunOpen[idx])}
                      >
                        <TreeItemLayout
                          iconBefore={run.explicitScore === undefined ? undefined : <Badge>{run.explicitScore}</Badge>}
                          iconAfter={<RunSummaryBadge run={run} baseline={test.baseline?.runs[idx]} />}
                        >
                          Test Run # {idx + 1}
                        </TreeItemLayout>
                      </TreeItem>
                    </div>
                  );
                })}
              </>
        }
      </Tree>
    </TreeItem>
  );
});
