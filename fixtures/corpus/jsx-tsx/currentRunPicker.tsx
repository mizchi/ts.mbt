type Props = {
  simulationRunsProvider: SimulationRunsProvider;
  outputFolderName: string;
  onChange: (selected: string | undefined) => void;
  disabled?: boolean;
};

export const CurrentRunPicker = mobxlite.observer(({ simulationRunsProvider, onChange, disabled, outputFolderName }: Props) => {
  const [isRenameDialogOpen, setIsRenameDialogOpen] = React.useState(false);
  const [newName, setNewName] = React.useState('');
  const [runToRename, setRunToRename] = React.useState<string>('');

  const handleRenameClick = (runName: string) => {
    setRunToRename(runName);
    setNewName(runName);
    setIsRenameDialogOpen(true);
  };

  return (
    <div className={styles.root}>
      <Dropdown
        selectedOptions={[outputFolderName]}
        disabled={disabled}
        onOptionSelect={(_e: SelectionEvents, { optionValue }: OptionOnSelectData) => onChange(optionValue)}
      >
        {simulationRunsProvider.runs.map((run) => (
          <Option key={run.name} value={run.name} text={run.friendlyName}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', width: '100%' }}>
              <span>{run.friendlyName}</span>
              <Button
                icon={<Edit16Regular />}
                onClick={(e) => {
                  e.stopPropagation();
                  handleRenameClick(run.name);
                }}
              >Rename ↵</Button>
            </div>
          </Option>
        ))}
      </Dropdown>
      <Dialog open={isRenameDialogOpen} onOpenChange={(_, { open }) => setIsRenameDialogOpen(open)}>
        <DialogSurface />
      </Dialog>
    </div>
  );
});
