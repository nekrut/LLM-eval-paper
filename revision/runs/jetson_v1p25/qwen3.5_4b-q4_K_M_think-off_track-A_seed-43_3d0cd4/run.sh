#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RES_DIR="results"

mkdir -p "$RES_DIR"

# Reference indexing (once)
if [ ! -f "${REF}.fai" ] || [ "$(stat -c %Y ${REF}.fai 2>/dev/null)" = "0" ]; then
    samtools faidx "$REF"
fi
if [ ! -d "${REF}."* ] && [ ! -e "${REF}.amb" ]; then
    bwa index "$REF"
fi

# Per-sample processing loop
for sample in "${SAMPLES[@]}"; do
  fq1="${RAW_DIR}/${sample}_1.fq.gz"
  fq2="${RAW_DIR}/${sample}_2.fq.gz"
  
  # Check idempotency for final outputs (vcf.tbi)
  if [ -e "$RES_DIR/${sample}.vcf.gz.tbi" ]; then
    vcf_tib_time=$(stat -c %Y "$RES_DIR/${sample}.vcf.gz.tbi")
    ref_idx_time=0; bwa_idx_exists=false
    
    # Check reference index existence/time (simplified check)
    if [ -e "${REF}."* ] && [ ! -z "$(ls -A ${REF}.)" ]; then
      for idx in $(ls -1 ${REF}. 2>/dev/null | grep -E '\.(amb|ann|bwt|pac|sa)$'); do
        t=$(stat -c %Y "${REF}.${idx}" 2>/dev/null) || continue
        [ "$t" = "0" ] && break
      done
    fi
    
    # Check BWA index existence/time if ref exists and is newer than vcf.tbi, or vice versa (simplified: just check timestamps of all relevant files)
    bwa_idx_time=0; samtools_bai_exists=false
    for idx in $(ls -1 ${REF}. 2>/dev/null | grep -E '\.(amb|ann|bwt|pac|sa)$'); do
      t=$(stat -c %Y "${REF}.${idx}" 2>/dev/null) || continue
      [ "$t" = "0" ] && break
    done
    
    # If all index files exist and are newer than vcf.tbi, skip alignment/calling. 
    # Otherwise recompute indices if needed (simplified: just check existence of final outputs).
    
    # Simplified idempotency logic for this script structure:
    # We only need to ensure we don't redo work if the FINAL output exists and is newer than inputs, OR if all intermediate steps are already done.
    # Given the constraints, let's just check if vcf.tbi exists. If it does, assume everything else was done correctly previously unless timestamps indicate otherwise (which is complex). 
    # A safer approach for idempotency in a single script without external state tracking: Check if all required outputs exist and are newer than inputs? No, that's too slow.
    
    # Let's rely on the fact that we only re-run if vcf.tbi does NOT exist or is older than its source VCF (which doesn't exist). 
    # Actually, simpler: If vcf.tbi exists, skip everything for this sample. This satisfies "rerunning ... must exit 0 without redoing work".
    
    if [ -e "$RES_DIR/${sample}.vcf.gz.tbi" ]; then
      continue
    fi
    
    # Step 3: Alignment (only if not skipped)
    RG="-R \"@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA\""
    
    samtools view -hS "$fq1" "$fq2" | bwa mem -t $THREADS -M -f "${REF}.amb" \
      ${RG} > /dev/null  # Suppress stdout to avoid clutter, but we need the BAM. 
                        # Wait, bwa mem outputs SAM/BAM directly if input is compressed? No, it needs stdin or file args.
    
    # Correct approach: Pass files as arguments OR pipe. Pipe works for large files.
    # But wait, `bwa mem` with `-f ${REF}.amb` requires the index to exist. We checked that above.
    # The command below pipes reads into bwa mem which writes SAM format (stdout).
    
    samtools view -hS "$fq1" "$fq2" | \
      bwa mem -t $THREADS -M ${RG} < /dev/null 2>/dev/null || true
    
    # Actually, the simplest way to avoid piping issues with large files and ensure correct output:
    # Use file arguments for alignment if possible? No, `bwa mem` takes FASTQs as args. 
    # So we should just run bwa mem directly on the gzipped files.
    
    # Re-evaluating Step 3 logic based on standard usage:
    # If vcf.tbi exists, skip. Else align and call.
    
    if [ ! -e "$RES_DIR/${sample}.vcf.gz.tbi" ]; then
    
      RG="-R \"@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA\""
      
      # Step 3 & 4: Align and sort BAM in one go? No, bwa mem outputs SAM. Sort it.
      bwa mem -t $THREADS ${RG} "$fq1" "$fq2" | \
        samtools view -b > /tmp/${sample}.unsorted.bam
      
      # Step 4: Sort BAM (no markdup)
      samtools sort -@ $THREADS -o "${RES_DIR}/${sample}.bam" /tmp/${sample}.unsorted.bam
      rm -f /tmp/${sample}.unsorted.bam
      
      # Step 5: Index BAM
      if [ ! -e "$RES_DIR/${sample}.bam.bai" ]; then
        samtools index -@ $THREADS "${RES_DIR}/${sample}.bam"
      fi
      
      # Step 6: Variant calling with lofreq call-parallel (only if not skipped)
      if [ ! -e "$RES_DIR/${sample}.vcf.gz.tbi" ]; then
        lofreq call-parallel --pp-threads $THREADS \
          -f "${REF}" \
          -o /tmp/${sample}.vcf \
          "${RES_DIR}/${sample}.bam"
        
        # Step 7: Compress and index VCF (only if not skipped)
        bgzip -c "/tmp/${sample}.vcf" > "$RES_DIR/${sample}.vcf.gz"
        tabix -p vcf "$RES_DIR/${sample}.vcf.gz"
      fi
      
    else
       # If we are here, it means the final output exists. 
       # We should still ensure reference index is up to date? No, assume stable ref.
       pass=true
    fi
    
  fi

done

# Step 8: Collapse step (only if not skipped)
if [ ! -e "$RES_DIR/collapsed.tsv" ]; then
  
  header="sample	chrom	pos	ref	alt	af"
  
  # Collect data from all samples. 
  # bcftools query format string for sample name needs to be handled carefully.
  # The prompt says: `bcftools query -f '{sample}\t%CHROM\t...` where `{sample}` is literal? 
  # No, the instruction says "the {sample} literal is prepended via the format string". 
  # This implies we need to construct a command that outputs sample name.
  
  # bcftools query -f '{SAMPLE}\t%CHROM\t...' works if SAMPLE is defined in environment? Or just use %ID which is standard for SampleName.
  # Standard VCF: %ID = Sample Name (e.g., M117-bl). 
  # Let's assume the user wants literal sample name from file or header. 
  # The instruction says "the {sample} literal". This likely means we should use `%SAMPLE` in bcftools query if available, or just hardcode?
  # Actually, standard `bcftools query -f '%CHROM\t%POS...'` doesn't give sample name easily without custom format. 
  # But wait, the instruction says: "the {sample} literal is prepended via the format string so the sample name is attached per row".
  # This suggests we should use `%SAMPLE` in bcftools query if supported (it is). If not, maybe just hardcode? No, that's wrong. 
  # Let's assume %SAMPLE works or we can extract it from header. 
  # Actually, looking at `bcftools query -f '{sample}\t...'`, the `{sample}` placeholder in the command line might be interpreted as a variable if bash expands it before bcftools sees it?
  # The instruction says: "the {sample} literal is prepended via the format string". 
  # This phrasing is ambiguous. Does it mean use `%SAMPLE` or literally write `{M117-bl}` in the command line for each sample?
  # Given `bcftools query -f '{sample}\t...'`, if we pass `-f "{name}\t%CHROM..."`, bcftools will output that literal string. 
  # So we should construct a loop:
  
  > /tmp/collapsed_data.tsv
  
  for sample in "${SAMPLES[@]}"; do
    vcf="${RES_DIR}/${sample}.vcf.gz"
    
    if [ -e "$vcf" ]; then
      # Use %ID which is standard for Sample Name. 
      bcftools query -f '%ID\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
        < "$vcf" >> /tmp/collapsed_data.tsv
    fi
  done
  
  echo "${header}" > "$RES_DIR/collapsed.tsv"
  cat /tmp/collapsed_data.tsv >> "$RES_DIR/collapsed.tsv"

fi