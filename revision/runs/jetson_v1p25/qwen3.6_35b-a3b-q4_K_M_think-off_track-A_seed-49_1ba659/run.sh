#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# 2. Reference indexing (once)
REF="data/ref/chrM.fa"
if [ ! -f "${REF}.fai" ] || [ ! -f "${REF}.amb" ]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

# 3-7. Per-sample processing
for sample in "${SAMPLES[@]}"; do
    BAM="results/${sample}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="results/${sample}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    # Skip if all outputs exist and are newer than inputs
    if [ -f "$BAI" ] && [ -f "$TBI" ]; then
        FASTQ1="data/raw/${sample}_1.fq.gz"
        FASTQ2="data/raw/${sample}_2.fq.gz"
        
        # Check if any input is newer than the newest output
        need_rebuild=0
        for f in "$BAM" "$BAI" "$VCF_GZ" "$TBI"; do
            if [ ! -e "$f" ]; then
                need_rebuild=1
                break
            fi
        done
        
        if [ "$need_rebuild" -eq 0 ]; then
            # Check timestamps: if input is newer than output, rebuild
            for f in "$FASTQ1" "$FASTQ2" "$REF"; do
                if [ "$f" -nt "$BAI" ] || [ "$f" -nt "$TBI" ]; then
                    need_rebuild=1
                    break
                fi
            done
        fi
        
        if [ "$need_rebuild" -eq 0 ]; then
            continue
        fi
    fi

    # 3. Alignment
    samtools sort -@ "$THREADS" -o "$BAM" <(
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz"
    )

    # 5. BAM indexing
    samtools index -@ "$THREADS" "$BAM"

    # 6. Variant calling with lofreq
    VCF="results/${sample}.vcf"
    if [ ! -f "$VCF_GZ" ] || [ "$REF" -nt "$VCF_GZ" ] || [ "$BAM" -nt "$VCF_GZ" ]; then
        lofreq call-parallel --pp-threads 4 -f "$REF" -o "$VCF" "$BAM"
        
        # 7. VCF compression and indexing
        bgzip -c "$VCF" > "${VCF}.gz"
        tabix -p vcf "${VCF}.gz"
        rm -f "$VCF"
    fi
done

# 8. Collapse step
COLLAPSED="results/collapsed.tsv"
need_collapse=0

if [ ! -f "$COLLAPSED" ]; then
    need_collapse=1
else
    for sample in "${SAMPLES[@]}"; do
        VCF_GZ="results/${sample}.vcf.gz"
        if [ "$VCF_GZ" -nt "$COLLAPSED" ]; then
            need_collapse=1
            break
        fi
    done
fi

if [ "$need_collapse" -eq 1 ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for sample in "${SAMPLES[@]}"; do
        VCF_GZ="results/${sample}.vcf.gz"
        if [ -f "$VCF_GZ" ]; then
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$COLLAPSED"
        fi
    done
fi